classdef faceDetectionApp < matlab.apps.AppBase
    %FACEDETECTIONAPP 人像美颜 GUI 主程序，负责单图与视频模式的加载、预览、评价和保存。
    %   设计遵循现代暗色调色台风格，分层解耦样式系统与元数据处理，并为视频美颜预留接口。

    properties (Access = public)
        % App Designer 兼容的核心 UI 组件句柄（必须严格保留以保持外部契约）
        UIFigure matlab.ui.Figure
        OpenImageButton matlab.ui.control.Button
        SaveImageButton matlab.ui.control.Button
        OneClickBeautyButton matlab.ui.control.Button
        ResetBeautyButton matlab.ui.control.Button
        SmoothingSlider matlab.ui.control.Slider
        WhiteningSlider matlab.ui.control.Slider
        SmoothingValueLabel matlab.ui.control.Label
        WhiteningValueLabel matlab.ui.control.Label

        % 兼容既有指标容器与标签句柄
        MetricsPanel matlab.ui.container.Panel
        EntropyLabel matlab.ui.control.Label
        StandardDeviationLabel matlab.ui.control.Label
        AverageGradientLabel matlab.ui.control.Label
        ElapsedTimeLabel matlab.ui.control.Label

        % 输入原图客观评价指标组件
        InputMetricsPanel matlab.ui.container.Panel
        InputEntropyLabel matlab.ui.control.Label
        InputStandardDeviationLabel matlab.ui.control.Label
        InputAverageGradientLabel matlab.ui.control.Label
        InputElapsedTimeLabel matlab.ui.control.Label

        % 输出处理结果客观评价指标组件
        OutputMetricsPanel matlab.ui.container.Panel
        OutputEntropyLabel matlab.ui.control.Label
        OutputStandardDeviationLabel matlab.ui.control.Label
        OutputAverageGradientLabel matlab.ui.control.Label
        OutputElapsedTimeLabel matlab.ui.control.Label

        % 核心视窗与状态栏
        SourceAxes matlab.ui.control.UIAxes
        DetectedAxes matlab.ui.control.UIAxes
        StatusLabel matlab.ui.control.Label

        % 新增：模式切换与媒体信息展示
        SingleImageModeButton matlab.ui.control.Button
        VideoModeButton matlab.ui.control.Button
        MediaInfoLabel matlab.ui.control.Label
        OpenVideoButton matlab.ui.control.Button
        ExportVideoButton matlab.ui.control.Button

        % 新增：视频时间轴播放器组件
        VideoToolbar matlab.ui.container.Panel
        VideoPlayButton matlab.ui.control.Button
        VideoStepBackButton matlab.ui.control.Button
        VideoStepForwardButton matlab.ui.control.Button
        VideoTimecodeLabel matlab.ui.control.Label
        VideoFrameLabel matlab.ui.control.Label
        VideoTimelineSlider matlab.ui.control.Slider

        % 新增：视频时域防闪烁开关
        DeflickerCheckBox matlab.ui.control.CheckBox

        % 当前工作模式 ('image' | 'video')
        CurrentMode = 'image'
    end

    properties (Access = private)
        % 缓存原始图像、当前结果和单个人脸框。
        sourceImage = []
        previewImage = []
        previewFaceBox = zeros(0, 4)
        previewContext = []
        previewScale = 1
        beautifiedImage = []
        faceBox = zeros(0, 4)
        beautyContext = []
        inputMetrics = []
        currentMetrics = []
        hasSingleFace = false

        % 记录输入文件信息，用于生成默认输出文件名。
        inputFormat = ''
        inputBaseName = ''
        inputImageInfo = []

        % 保存最近一次处理诊断，便于确认缓存是否被复用或重建。
        lastDiagnostics = []

        % 记录上次拖动预览时间，限制实时刷新频率。
        previewClock = []

        videoHook = []
    end

    methods (Access = private)
        function scaledBox = scaleFaceBox(~, faceBox, scale, imageSize)
            scaledBox = round(double(faceBox) * scale);
            scaledBox(1) = max(1, min(scaledBox(1), imageSize(2)));
            scaledBox(2) = max(1, min(scaledBox(2), imageSize(1)));
            x2 = min(imageSize(2), scaledBox(1) + scaledBox(3) - 1);
            y2 = min(imageSize(1), scaledBox(2) + scaledBox(4) - 1);
            scaledBox(3:4) = max(1, [x2 - scaledBox(1) + 1, ...
                y2 - scaledBox(2) + 1]);
        end

        function ensureSourcePath(~)
            % 根据 GUI 文件位置注册算法目录，不依赖 MATLAB 当前工作目录。
            guiFolder = fileparts(mfilename('fullpath'));
            sourceFolder = fullfile(fileparts(guiFolder), 'src');
            if ~isfolder(sourceFolder)
                error('faceDetectionApp:MissingSourceFolder', ...
                    'The project src folder was not found beside the gui folder.');
            end
            addpath(sourceFolder);
            addpath(guiFolder);
        end

        % =================== 图像打开与处理 ===================
        function openImageButtonPushed(app, ~)
            [fileName, folderPath] = uigetfile( ...
                {'*.jpg;*.jpeg;*.png', 'JPG and PNG Images (*.jpg, *.jpeg, *.png)'}, ...
                'Open Image');
            if isequal(fileName, 0)
                return;
            end
            app.openImageFromPath(fullfile(folderPath, fileName));
        end

        function openImageFromPath(app, filePath)
            try
                inputImage = imread(filePath);
                imageInfo = imfinfo(filePath);
            catch exception
                app.clearLoadedImage();
                uialert(app.UIFigure, exception.message, 'Unable to Open Image');
                return;
            end

            if ~isa(inputImage, 'uint8') || ndims(inputImage) ~= 3 || ...
                    size(inputImage, 3) ~= 3
                app.clearLoadedImage();
                uialert(app.UIFigure, ...
                    'Only uint8 three-channel RGB JPG and PNG images are supported.', ...
                    'Unsupported Image');
                return;
            end

            app.clearLoadedImage();
            [~, baseName, extension] = fileparts(filePath);
            app.sourceImage = inputImage;
            app.inputImageInfo = imageInfo;
            app.previewScale = min(1, 640 / max(size(inputImage, 1), size(inputImage, 2)));
            if app.previewScale < 1
                app.previewImage = imresize(inputImage, app.previewScale, 'bilinear');
            else
                app.previewImage = inputImage;
            end
            app.inputBaseName = baseName;
            app.inputFormat = gui_helpers.ImageMetadataHelper.normalizedFormat(extension);
            app.showImage(app.SourceAxes, inputImage, 'Original Image (输入原图)');
            app.MediaInfoLabel.Text = sprintf('%s | %dx%d RGB', [baseName extension], size(inputImage,2), size(inputImage,1));
            app.StatusLabel.Text = 'Detecting face...';
            drawnow;

            if exist('vision.CascadeObjectDetector', 'class') == 0
                app.clearDetectionResult();
                uialert(app.UIFigure, ...
                    'Computer Vision Toolbox is required for face detection.', ...
                    'Missing Toolbox');
                return;
            end
            try
                [detectedFaceBox, isSingleFace, detectionDetails] = ...
                    detectSingleFace(app.previewImage);
            catch exception
                app.clearDetectionResult();
                uialert(app.UIFigure, exception.message, 'Detection Failed');
                return;
            end

            app.hasSingleFace = isSingleFace;
            if ~isSingleFace
                app.clearDetectionResult();
                uialert(app.UIFigure, detectionDetails.message, 'Single Face Required');
                return;
            end

            app.previewFaceBox = detectedFaceBox;
            app.faceBox = app.scaleFaceBox(detectedFaceBox, ...
                1 / app.previewScale, size(app.sourceImage));

            app.calculateInputMetrics();
            try
                app.previewContext = prepareBeautyContext( ...
                    app.previewImage, app.previewFaceBox);
                app.beautyContext = resizeBeautyContext( ...
                    app.previewContext, size(app.sourceImage), app.faceBox, ...
                    app.sourceImage);
            catch exception
                app.clearDetectionResult();
                uialert(app.UIFigure, exception.message, 'Context Preparation Failed');
                return;
            end

            app.setControlsEnable('on');
            app.StatusLabel.Text = 'Ready: face detected. Adjust beauty parameters.';
            app.updateBeautyPreview();
        end

        function clearLoadedImage(app)
            app.sourceImage = [];
            app.previewImage = [];
            app.previewScale = 1;
            app.inputFormat = '';
            app.inputBaseName = '';
            app.inputImageInfo = [];
            app.clearDetectionResult();
            app.resetMetricsLabels();
            cla(app.SourceAxes);
            title(app.SourceAxes, 'Original Image (输入原图)');
            cla(app.DetectedAxes);
            title(app.DetectedAxes, 'Beauty Preview (效果实时预览)');
            app.MediaInfoLabel.Text = 'No Media Loaded';
        end

        function clearDetectionResult(app)
            app.previewFaceBox = zeros(0, 4);
            app.previewContext = [];
            app.beautifiedImage = [];
            app.faceBox = zeros(0, 4);
            app.beautyContext = [];
            app.inputMetrics = [];
            app.currentMetrics = [];
            app.hasSingleFace = false;
            app.lastDiagnostics = [];
            app.previewClock = [];
            cla(app.DetectedAxes);
            title(app.DetectedAxes, 'Beauty Preview (效果实时预览)');
            app.setControlsEnable('off');
            app.StatusLabel.Text = 'Open a uint8 RGB JPG or PNG image.';
        end

        function calculateInputMetrics(app)
            if isempty(app.sourceImage)
                return;
            end
            app.inputMetrics = evaluateImage(app.sourceImage, app.sourceImage, 0);
            app.InputEntropyLabel.Text = sprintf('Entropy: %.4f', ...
                app.inputMetrics.entropy);
            app.InputStandardDeviationLabel.Text = sprintf('Standard deviation: %.4f', ...
                app.inputMetrics.standardDeviation);
            app.InputAverageGradientLabel.Text = sprintf('Average gradient: %.4f', ...
                app.inputMetrics.averageGradient);
            app.InputElapsedTimeLabel.Text = 'Single-image time: --';
        end

        function beautySliderValueChanging(app, event, isSmoothing)
            % 拖拽中限频实时更新
            if ~app.hasSingleFace || isempty(app.sourceImage)
                return;
            end
            if isSmoothing
                app.SmoothingValueLabel.Text = sprintf('Smoothing: %d', round(event.Value));
            else
                app.WhiteningValueLabel.Text = sprintf('Whitening: %d', round(event.Value));
            end
            nowClock = tic;
            if ~isempty(app.previewClock) && toc(app.previewClock) < 0.05
                return;
            end
            app.previewClock = nowClock;
            app.updateBeautyPreview(event.Value, isSmoothing);
        end

        function beautySliderValueChanged(app, ~)
            if ~app.hasSingleFace || isempty(app.sourceImage)
                return;
            end
            app.SmoothingValueLabel.Text = sprintf('Smoothing: %d', round(app.SmoothingSlider.Value));
            app.WhiteningValueLabel.Text = sprintf('Whitening: %d', round(app.WhiteningSlider.Value));
            app.updateBeautyPreview();
        end

        function updateBeautyPreview(app, liveValue, isSmoothing)
            if ~app.hasSingleFace || isempty(app.sourceImage)
                return;
            end

            smoothing = app.SmoothingSlider.Value;
            whitening = app.WhiteningSlider.Value;
            if nargin >= 3
                if isSmoothing
                    smoothing = liveValue;
                else
                    whitening = liveValue;
                end
            end
            params = struct('smoothingStrength', smoothing, ...
                'whiteningStrength', whitening);

            pipelineStart = tic;
            try
                [outputImage, diagnostics] = beautifyImage( ...
                    app.previewImage, params, app.previewFaceBox, app.previewContext);
            catch exception
                uialert(app.UIFigure, exception.message, 'Beauty Processing Failed');
                return;
            end
            elapsedTime = toc(pipelineStart);

            app.beautifiedImage = outputImage;
            app.lastDiagnostics = diagnostics;
            app.showImage(app.DetectedAxes, outputImage, 'Beauty Preview (效果实时预览)');
            app.updateMetrics(elapsedTime);
        end

        function updateMetrics(app, elapsedTime)
            if isempty(app.previewImage) || isempty(app.beautifiedImage)
                return;
            end
            metrics = evaluateImage(app.previewImage, app.beautifiedImage, elapsedTime);
            app.currentMetrics = metrics;
            app.OutputEntropyLabel.Text = sprintf('Entropy: %.4f', metrics.entropy);
            app.OutputStandardDeviationLabel.Text = sprintf('Standard deviation: %.4f', metrics.standardDeviation);
            app.OutputAverageGradientLabel.Text = sprintf('Average gradient: %.4f', metrics.averageGradient);
            app.OutputElapsedTimeLabel.Text = sprintf('Single-image time: %.3f s', metrics.elapsedSeconds);

            % 兼容旧版标签引用
            app.EntropyLabel.Text = app.OutputEntropyLabel.Text;
            app.StandardDeviationLabel.Text = app.OutputStandardDeviationLabel.Text;
            app.AverageGradientLabel.Text = app.OutputAverageGradientLabel.Text;
            app.ElapsedTimeLabel.Text = app.OutputElapsedTimeLabel.Text;
        end

        function resetMetricsLabels(app)
            app.EntropyLabel.Text = 'Entropy: --';
            app.StandardDeviationLabel.Text = 'Standard deviation: --';
            app.AverageGradientLabel.Text = 'Average gradient: --';
            app.ElapsedTimeLabel.Text = 'Single-image time: --';

            app.InputEntropyLabel.Text = 'Entropy: --';
            app.InputStandardDeviationLabel.Text = 'Standard deviation: --';
            app.InputAverageGradientLabel.Text = 'Average gradient: --';
            app.InputElapsedTimeLabel.Text = 'Single-image time: --';

            app.OutputEntropyLabel.Text = 'Entropy: --';
            app.OutputStandardDeviationLabel.Text = 'Standard deviation: --';
            app.OutputAverageGradientLabel.Text = 'Average gradient: --';
            app.OutputElapsedTimeLabel.Text = 'Single-image time: --';
        end

        function oneClickBeautyButtonPushed(app, ~)
            app.applyOneClickBeauty();
        end

        function resetBeautyButtonPushed(app, ~)
            app.resetBeauty();
        end

        function saveImageButtonPushed(app, ~)
            if ~app.hasSingleFace || isempty(app.beautifiedImage)
                uialert(app.UIFigure, ...
                    'Open an image with a detectable face before saving.', ...
                    'No Image to Save');
                return;
            end

            defaultExt = app.inputFormat;
            if isempty(defaultExt)
                defaultExt = 'png';
            end
            defaultName = sprintf('%s_beautified.%s', app.inputBaseName, defaultExt);

            [fileName, folderPath, filterIndex] = uiputfile( ...
                {'*.jpg', 'JPEG Image (*.jpg)'; '*.png', 'PNG Image (*.png)'}, ...
                'Save Beauty Result', defaultName);
            if isequal(fileName, 0)
                return;
            end

            [~, outputBaseName, extension] = fileparts(fileName);
            if isempty(extension)
                if filterIndex == 1
                    extension = '.jpg';
                else
                    extension = '.png';
                end
            elseif ~ismember(lower(extension), {'.jpg', '.jpeg', '.png'})
                uialert(app.UIFigure, ...
                    'Save the result as a JPG or PNG image.', ...
                    'Unsupported Output Format');
                return;
            end
            outputPath = fullfile(folderPath, [outputBaseName, extension]);

            try
                app.saveImageToPath(outputPath);
            catch exception
                uialert(app.UIFigure, exception.message, 'Unable to Save Image');
                return;
            end
        end

        function saveImageToPath(app, outputPath)
            % 保存原尺寸结果，并在写盘后校验尺寸、比例和分辨率。
            if ~app.hasSingleFace || isempty(app.beautifiedImage)
                error('faceDetectionApp:NoBeautyResult', ...
                    '保存前必须先打开包含可识别人脸的图像。');
            end
            if ~(ischar(outputPath) && size(outputPath, 1) == 1) && ...
                    ~(isstring(outputPath) && isscalar(outputPath))
                error('faceDetectionApp:InvalidOutputPath', ...
                    '输出路径必须是字符向量或字符串标量。');
            end
            outputPath = char(outputPath);
            [~, ~, extension] = fileparts(outputPath);
            if ~ismember(lower(extension), {'.jpg', '.jpeg', '.png'})
                error('faceDetectionApp:UnsupportedOutputFormat', ...
                    '输出结果必须保存为 JPG 或 PNG。');
            end

            fullContext = resizeBeautyContext(app.previewContext, ...
                size(app.sourceImage), app.faceBox, app.sourceImage);
            fullParams = struct('smoothingStrength', app.SmoothingSlider.Value, ...
                'whiteningStrength', app.WhiteningSlider.Value);
            [outputImage, saveDiagnostics] = beautifyImage( ...
                app.sourceImage, fullParams, app.faceBox, fullContext);
            app.lastDiagnostics = saveDiagnostics;

            % 调用解耦的元数据写入工具
            gui_helpers.ImageMetadataHelper.writeImageWithResolution(outputImage, outputPath, ...
                app.inputImageInfo);
            outputImage = imread(outputPath);
            outputInfo = imfinfo(outputPath);

            inputSize = size(app.sourceImage);
            outputSize = size(outputImage);
            samePixels = numel(outputSize) >= 3 && ...
                outputSize(1) == inputSize(1) && outputSize(2) == inputSize(2);
            sameChannels = ndims(outputImage) == 3 && outputSize(3) == 3;
            sameAspectRatio = outputSize(2) * inputSize(1) == ...
                inputSize(2) * outputSize(1);
            sameResolution = gui_helpers.ImageMetadataHelper.hasSameResolution( ...
                app.inputImageInfo, outputInfo);
            if ~samePixels || ~sameChannels || ~sameAspectRatio || ...
                    ~sameResolution
                error('faceDetectionApp:SaveVerificationFailed', ...
                    'The saved image does not preserve the input size, aspect ratio, or resolution.');
            end

            app.StatusLabel.Text = sprintf('Saved: %s', outputPath);
        end

        function setControlsEnable(app, state)
            app.SaveImageButton.Enable = state;
            app.OneClickBeautyButton.Enable = state;
            app.ResetBeautyButton.Enable = state;
            app.SmoothingSlider.Enable = state;
            app.WhiteningSlider.Enable = state;
        end

        function showImage(~, targetAxes, imageData, titleText)
            % 在指定 UIAxes 中按原比例显示图像并注入暗色视窗样式。
            imageHandle = findobj(targetAxes, 'Type', 'image');
            if ~isempty(imageHandle) && isvalid(imageHandle(1))
                imageHandle(1).CData = imageData;
            else
                cla(targetAxes);
                image(targetAxes, imageData);
            end
            axis(targetAxes, 'image');
            axis(targetAxes, 'off');
            gui_helpers.GuiTheme.applyAxesStyle(targetAxes, titleText);
        end

        % =================== 视频接口事件桩 ===================
        function openVideoButtonPushed(app, ~)
            [fileName, folderPath] = uigetfile( ...
                {'*.mp4;*.avi;*.mov', 'Video Files (*.mp4, *.avi, *.mov)'}, ...
                'Open Video');
            if isequal(fileName, 0)
                return;
            end
            filePath = fullfile(folderPath, fileName);
            if app.videoHook.openVideoFile(app, filePath)
                app.MediaInfoLabel.Text = sprintf('%s | %d 帧 | %.1f FPS', ...
                    fileName, app.videoHook.TotalFrames, app.videoHook.FrameRate);
                app.VideoTimelineSlider.Limits = [1, app.videoHook.TotalFrames];
                app.VideoTimelineSlider.Value = 1;
                app.VideoFrameLabel.Text = sprintf('帧: 1 / %d', app.videoHook.TotalFrames);
                app.VideoTimecodeLabel.Text = app.videoHook.formatTimecode(1);
                app.StatusLabel.Text = sprintf('视频源已加载: %s', fileName);
                % 提取第一帧进行主脸定位与预览
                try
                    app.videoHook.VideoReaderObj.CurrentTime = 0;
                    firstFrame = readFrame(app.videoHook.VideoReaderObj);
                    app.sourceImage = firstFrame;
                    app.previewImage = firstFrame;
                    app.showImage(app.SourceAxes, firstFrame, 'Video Raw Frame (视频原帧)');
                    app.showImage(app.DetectedAxes, firstFrame, 'Video Beautified (时域美颜效果)');
                    app.setControlsEnable('on');
                catch
                end
            end
        end

        function exportVideoButtonPushed(app, ~)
            [fileName, folderPath] = uiputfile('*.mp4', 'Export Beautified Video', 'beautified_video.mp4');
            if isequal(fileName, 0), return; end
            app.videoHook.exportVideo(app, fullfile(folderPath, fileName));
        end

        function videoPlayButtonPushed(app, ~)
            app.videoHook.togglePlay(app);
        end

        function videoStepBackButtonPushed(app, ~)
            app.videoHook.stepFrame(app, -1);
        end

        function videoStepForwardButtonPushed(app, ~)
            app.videoHook.stepFrame(app, 1);
        end

        function videoTimelineChanged(app, event)
            target = round(event.Value);
            app.videoHook.seekFrame(app, target);
        end

        % =================== GUI 整体组件装配 ===================
        function createComponents(app)
            % 实例化视频状态机
            app.videoHook = gui_helpers.VideoInterfaceHook();

            % 创建主窗口 (1260x820)
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [80, 80, 1260, 820];
            gui_helpers.GuiTheme.applyFigureStyle(app.UIFigure, 'VisionGlow Studio - 人脸美颜工作台');

            % 整体三行布局：[顶栏: fit, 主工作区: 1x, 状态栏: fit]
            rootGrid = uigridlayout(app.UIFigure, [3, 1]);
            gui_helpers.GuiTheme.applyGridLayout(rootGrid, gui_helpers.GuiTheme.BgRoot);
            rootGrid.RowHeight = {'fit', '1x', 'fit'};
            rootGrid.Padding = [12, 10, 12, 10];
            rootGrid.RowSpacing = 8;

            % 1. 顶栏
            app.createHeaderBar(rootGrid);

            % 2. 主工作区（左展示区 1x + 右控制侧栏 320px）
            app.createMainWorkspace(rootGrid);

            % 3. 底部状态栏
            app.createStatusBar(rootGrid);

            % 默认切到单图模式
            app.switchMode('image');
            app.UIFigure.Visible = 'on';
        end

        function createHeaderBar(app, parentGrid)
            headerCard = uipanel(parentGrid);
            gui_helpers.GuiTheme.applyPanelStyle(headerCard);
            headerCard.Layout.Row = 1;
            headerCard.Layout.Column = 1;

            headerGrid = uigridlayout(headerCard, [1, 5]);
            gui_helpers.GuiTheme.applyGridLayout(headerGrid, gui_helpers.GuiTheme.BgCard);
            headerGrid.RowHeight = {'fit'};
            headerGrid.ColumnWidth = {'fit', 'fit', '1x', 'fit', 'fit'};
            headerGrid.Padding = [10, 6, 10, 6];
            headerGrid.ColumnSpacing = 12;

            % 标题 Logo
            titleLabel = uilabel(headerGrid);
            titleLabel.Text = 'VisionGlow Studio';
            gui_helpers.GuiTheme.applyLabelStyle(titleLabel, 'highlight');
            titleLabel.FontSize = 13;

            % 模式切换按钮组
            modeGroup = uigridlayout(headerGrid, [1, 2]);
            gui_helpers.GuiTheme.applyGridLayout(modeGroup, gui_helpers.GuiTheme.BgCard);
            modeGroup.Padding = [0, 0, 0, 0];
            modeGroup.ColumnSpacing = 4;
            modeGroup.RowHeight = {'fit'};
            modeGroup.ColumnWidth = {'fit', 'fit'};

            app.SingleImageModeButton = uibutton(modeGroup, 'push');
            app.SingleImageModeButton.Text = '单图模式';
            gui_helpers.GuiTheme.applyButtonStyle(app.SingleImageModeButton, 'active_mode');
            app.SingleImageModeButton.ButtonPushedFcn = @(~,~) app.switchMode('image');

            app.VideoModeButton = uibutton(modeGroup, 'push');
            app.VideoModeButton.Text = '视频模式 (规划中)';
            gui_helpers.GuiTheme.applyButtonStyle(app.VideoModeButton, 'secondary');
            app.VideoModeButton.ButtonPushedFcn = @(~,~) app.switchMode('video');

            % 媒体源元数据信息
            app.MediaInfoLabel = uilabel(headerGrid);
            app.MediaInfoLabel.Text = 'No Media Loaded';
            app.MediaInfoLabel.HorizontalAlignment = 'center';
            gui_helpers.GuiTheme.applyLabelStyle(app.MediaInfoLabel, 'muted');

            % 单图操作按钮 (固定占位第 4 和第 5 列)
            app.OpenImageButton = uibutton(headerGrid, 'push');
            app.OpenImageButton.Text = '打开图像...';
            app.OpenImageButton.Layout.Row = 1;
            app.OpenImageButton.Layout.Column = 4;
            gui_helpers.GuiTheme.applyButtonStyle(app.OpenImageButton, 'secondary');
            app.OpenImageButton.ButtonPushedFcn = @(~, event) app.openImageButtonPushed(event);

            app.SaveImageButton = uibutton(headerGrid, 'push');
            app.SaveImageButton.Text = '保存结果';
            app.SaveImageButton.Layout.Row = 1;
            app.SaveImageButton.Layout.Column = 5;
            gui_helpers.GuiTheme.applyButtonStyle(app.SaveImageButton, 'primary');
            app.SaveImageButton.Enable = 'off';
            app.SaveImageButton.ButtonPushedFcn = @(~, event) app.saveImageButtonPushed(event);

            % 视频操作按钮（初始隐藏，共用第 4 和第 5 列避免换行）
            app.OpenVideoButton = uibutton(headerGrid, 'push');
            app.OpenVideoButton.Text = '打开视频...';
            app.OpenVideoButton.Layout.Row = 1;
            app.OpenVideoButton.Layout.Column = 4;
            gui_helpers.GuiTheme.applyButtonStyle(app.OpenVideoButton, 'secondary');
            app.OpenVideoButton.Visible = 'off';
            app.OpenVideoButton.ButtonPushedFcn = @(~, event) app.openVideoButtonPushed(event);

            app.ExportVideoButton = uibutton(headerGrid, 'push');
            app.ExportVideoButton.Text = '导出视频';
            app.ExportVideoButton.Layout.Row = 1;
            app.ExportVideoButton.Layout.Column = 5;
            gui_helpers.GuiTheme.applyButtonStyle(app.ExportVideoButton, 'primary');
            app.ExportVideoButton.Visible = 'off';
            app.ExportVideoButton.ButtonPushedFcn = @(~, event) app.exportVideoButtonPushed(event);
        end

        function createMainWorkspace(app, parentGrid)
            workspaceGrid = uigridlayout(parentGrid, [1, 2]);
            gui_helpers.GuiTheme.applyGridLayout(workspaceGrid, gui_helpers.GuiTheme.BgRoot);
            workspaceGrid.Layout.Row = 2;
            workspaceGrid.Layout.Column = 1;
            workspaceGrid.RowHeight = {'1x'};
            workspaceGrid.ColumnWidth = {'1x', 320};
            workspaceGrid.Padding = [0, 0, 0, 0];
            workspaceGrid.ColumnSpacing = 12;

            % 左主展示区
            app.createDisplayAndMetricsArea(workspaceGrid);

            % 右参数控制侧栏
            app.createParametersSidebar(workspaceGrid);
        end

        function createDisplayAndMetricsArea(app, parentGrid)
            % 左侧展示区布局：[双视窗: 1x, 视频时间轴: fit, 双客观指标卡片: fit]
            leftGrid = uigridlayout(parentGrid, [3, 1]);
            gui_helpers.GuiTheme.applyGridLayout(leftGrid, gui_helpers.GuiTheme.BgRoot);
            leftGrid.Layout.Row = 1;
            leftGrid.Layout.Column = 1;
            leftGrid.RowHeight = {'1x', 'fit', 'fit'};
            leftGrid.Padding = [0, 0, 0, 0];
            leftGrid.RowSpacing = 8;

            % 1. 双视窗并排 (SourceAxes & DetectedAxes)
            axesGrid = uigridlayout(leftGrid, [1, 2]);
            gui_helpers.GuiTheme.applyGridLayout(axesGrid, gui_helpers.GuiTheme.BgRoot);
            axesGrid.Layout.Row = 1;
            axesGrid.Layout.Column = 1;
            axesGrid.RowHeight = {'1x'};
            axesGrid.ColumnWidth = {'1x', '1x'};
            axesGrid.Padding = [0, 0, 0, 0];
            axesGrid.ColumnSpacing = 8;

            app.SourceAxes = uiaxes(axesGrid);
            gui_helpers.GuiTheme.applyAxesStyle(app.SourceAxes, 'Original Image (输入原图)');

            app.DetectedAxes = uiaxes(axesGrid);
            gui_helpers.GuiTheme.applyAxesStyle(app.DetectedAxes, 'Beauty Preview (效果实时预览)');

            % 2. 视频时间轴工具栏（仅在视频模式下 Visible='on'）
            app.VideoToolbar = uipanel(leftGrid);
            gui_helpers.GuiTheme.applySubPanelStyle(app.VideoToolbar);
            app.VideoToolbar.Layout.Row = 2;
            app.VideoToolbar.Layout.Column = 1;
            app.VideoToolbar.Visible = 'off';

            vidGrid = uigridlayout(app.VideoToolbar, [1, 6]);
            gui_helpers.GuiTheme.applyGridLayout(vidGrid, gui_helpers.GuiTheme.BgCardSub);
            vidGrid.RowHeight = {'fit'};
            vidGrid.ColumnWidth = {'fit', 'fit', 'fit', '1x', 'fit', 'fit'};
            vidGrid.Padding = [8, 4, 8, 4];
            vidGrid.ColumnSpacing = 8;

            app.VideoStepBackButton = uibutton(vidGrid, 'push');
            app.VideoStepBackButton.Text = '◀ -1F';
            gui_helpers.GuiTheme.applyButtonStyle(app.VideoStepBackButton, 'secondary');
            app.VideoStepBackButton.ButtonPushedFcn = @(~,~) app.videoStepBackButtonPushed();

            app.VideoPlayButton = uibutton(vidGrid, 'push');
            app.VideoPlayButton.Text = '播放预览';
            gui_helpers.GuiTheme.applyButtonStyle(app.VideoPlayButton, 'primary');
            app.VideoPlayButton.ButtonPushedFcn = @(~,~) app.videoPlayButtonPushed();

            app.VideoStepForwardButton = uibutton(vidGrid, 'push');
            app.VideoStepForwardButton.Text = '+1F ▶';
            gui_helpers.GuiTheme.applyButtonStyle(app.VideoStepForwardButton, 'secondary');
            app.VideoStepForwardButton.ButtonPushedFcn = @(~,~) app.videoStepForwardButtonPushed();

            app.VideoTimelineSlider = uislider(vidGrid);
            app.VideoTimelineSlider.Limits = [1, 100];
            app.VideoTimelineSlider.Value = 1;
            gui_helpers.GuiTheme.applySliderStyle(app.VideoTimelineSlider);
            app.VideoTimelineSlider.ValueChangedFcn = @(~, e) app.videoTimelineChanged(e);

            app.VideoTimecodeLabel = uilabel(vidGrid);
            app.VideoTimecodeLabel.Text = '00:00:00:00';
            gui_helpers.GuiTheme.applyLabelStyle(app.VideoTimecodeLabel, 'highlight');

            app.VideoFrameLabel = uilabel(vidGrid);
            app.VideoFrameLabel.Text = '帧: 1 / 1';
            gui_helpers.GuiTheme.applyLabelStyle(app.VideoFrameLabel, 'muted');

            % 3. 客观指标卡片区（双卡片横向排布）
            metricsGrid = uigridlayout(leftGrid, [1, 2]);
            gui_helpers.GuiTheme.applyGridLayout(metricsGrid, gui_helpers.GuiTheme.BgRoot);
            metricsGrid.Layout.Row = 3;
            metricsGrid.Layout.Column = 1;
            metricsGrid.RowHeight = {'fit'};
            metricsGrid.ColumnWidth = {'1x', '1x'};
            metricsGrid.Padding = [0, 0, 0, 0];
            metricsGrid.ColumnSpacing = 8;

            % 原图指标卡片
            inputCard = app.createStandardMetricsCard( ...
                metricsGrid, 1, 1, 'InputMetricsPanel (原图客观指标基准)', 'amber');
            app.InputMetricsPanel = inputCard.panel;
            app.InputEntropyLabel = inputCard.entropy;
            app.InputStandardDeviationLabel = inputCard.stdDev;
            app.InputAverageGradientLabel = inputCard.gradient;
            app.InputElapsedTimeLabel = inputCard.time;

            % 效果指标卡片
            outputCard = app.createStandardMetricsCard( ...
                metricsGrid, 1, 2, 'OutputMetricsPanel (美颜效果客观指标)', 'highlight');
            app.OutputMetricsPanel = outputCard.panel;
            app.OutputEntropyLabel = outputCard.entropy;
            app.OutputStandardDeviationLabel = outputCard.stdDev;
            app.OutputAverageGradientLabel = outputCard.gradient;
            app.OutputElapsedTimeLabel = outputCard.time;

            % 兼容旧句柄
            app.MetricsPanel = app.OutputMetricsPanel;
            app.EntropyLabel = app.OutputEntropyLabel;
            app.StandardDeviationLabel = app.OutputStandardDeviationLabel;
            app.AverageGradientLabel = app.OutputAverageGradientLabel;
            app.ElapsedTimeLabel = app.OutputElapsedTimeLabel;
        end

        function card = createStandardMetricsCard(~, parentGrid, row, col, titleText, styleRole)
            panel = uipanel(parentGrid);
            gui_helpers.GuiTheme.applyPanelStyle(panel, titleText);
            panel.Layout.Row = row;
            panel.Layout.Column = col;

            metricsGrid = uigridlayout(panel, [2, 2]);
            gui_helpers.GuiTheme.applyGridLayout(metricsGrid, gui_helpers.GuiTheme.BgCard);
            metricsGrid.RowHeight = {'fit', 'fit'};
            metricsGrid.ColumnWidth = {'1x', '1x'};
            metricsGrid.Padding = [10, 6, 10, 6];
            metricsGrid.RowSpacing = 4;
            metricsGrid.ColumnSpacing = 8;

            entropyLabel = uilabel(metricsGrid);
            entropyLabel.Text = 'Entropy: --';
            gui_helpers.GuiTheme.applyLabelStyle(entropyLabel, styleRole);

            stdDevLabel = uilabel(metricsGrid);
            stdDevLabel.Text = 'Standard deviation: --';
            gui_helpers.GuiTheme.applyLabelStyle(stdDevLabel, styleRole);

            gradientLabel = uilabel(metricsGrid);
            gradientLabel.Text = 'Average gradient: --';
            gui_helpers.GuiTheme.applyLabelStyle(gradientLabel, styleRole);

            timeLabel = uilabel(metricsGrid);
            timeLabel.Text = 'Single-image time: --';
            gui_helpers.GuiTheme.applyLabelStyle(timeLabel, styleRole);

            card = struct( ...
                'panel', panel, ...
                'entropy', entropyLabel, ...
                'stdDev', stdDevLabel, ...
                'gradient', gradientLabel, ...
                'time', timeLabel);
        end

        function createParametersSidebar(app, parentGrid)
            sidebarCard = uipanel(parentGrid);
            gui_helpers.GuiTheme.applyPanelStyle(sidebarCard, '美颜核心控制参数');
            sidebarCard.Layout.Row = 1;
            sidebarCard.Layout.Column = 2;

            sideGrid = uigridlayout(sidebarCard, [7, 1]);
            gui_helpers.GuiTheme.applyGridLayout(sideGrid, gui_helpers.GuiTheme.BgCard);
            sideGrid.RowHeight = {'fit', 'fit', 'fit', 'fit', 'fit', 'fit', '1x'};
            sideGrid.Padding = [12, 12, 12, 12];
            sideGrid.RowSpacing = 14;

            % 1. 磨皮控制区
            smoothBox = uipanel(sideGrid);
            gui_helpers.GuiTheme.applySubPanelStyle(smoothBox);
            smoothGrid = uigridlayout(smoothBox, [3, 1]);
            gui_helpers.GuiTheme.applyGridLayout(smoothGrid, gui_helpers.GuiTheme.BgCardSub);
            smoothGrid.RowHeight = {'fit', 'fit', 'fit'};
            smoothGrid.Padding = [8, 8, 8, 8];
            smoothGrid.RowSpacing = 4;

            app.SmoothingValueLabel = uilabel(smoothGrid);
            app.SmoothingValueLabel.Text = 'Smoothing: 25';
            gui_helpers.GuiTheme.applyLabelStyle(app.SmoothingValueLabel, 'highlight');

            app.SmoothingSlider = uislider(smoothGrid);
            app.SmoothingSlider.Limits = [0, 100];
            app.SmoothingSlider.Value = 25;
            app.SmoothingSlider.MajorTicks = 0:20:100;
            app.SmoothingSlider.Enable = 'off';
            gui_helpers.GuiTheme.applySliderStyle(app.SmoothingSlider);
            app.SmoothingSlider.ValueChangingFcn = @(~, event) ...
                app.beautySliderValueChanging(event, true);
            app.SmoothingSlider.ValueChangedFcn = @(~, event) ...
                app.beautySliderValueChanged(event);

            smoothDesc = uilabel(smoothGrid);
            smoothDesc.Text = '淡化细纹斑点，智能保护五官轮廓';
            gui_helpers.GuiTheme.applyLabelStyle(smoothDesc, 'muted');

            % 2. 美白控制区
            whiteBox = uipanel(sideGrid);
            gui_helpers.GuiTheme.applySubPanelStyle(whiteBox);
            whiteGrid = uigridlayout(whiteBox, [3, 1]);
            gui_helpers.GuiTheme.applyGridLayout(whiteGrid, gui_helpers.GuiTheme.BgCardSub);
            whiteGrid.RowHeight = {'fit', 'fit', 'fit'};
            whiteGrid.Padding = [8, 8, 8, 8];
            whiteGrid.RowSpacing = 4;

            app.WhiteningValueLabel = uilabel(whiteGrid);
            app.WhiteningValueLabel.Text = 'Whitening: 15';
            gui_helpers.GuiTheme.applyLabelStyle(app.WhiteningValueLabel, 'highlight');

            app.WhiteningSlider = uislider(whiteGrid);
            app.WhiteningSlider.Limits = [0, 100];
            app.WhiteningSlider.Value = 15;
            app.WhiteningSlider.MajorTicks = 0:20:100;
            app.WhiteningSlider.Enable = 'off';
            gui_helpers.GuiTheme.applySliderStyle(app.WhiteningSlider);
            app.WhiteningSlider.ValueChangingFcn = @(~, event) ...
                app.beautySliderValueChanging(event, false);
            app.WhiteningSlider.ValueChangedFcn = @(~, event) ...
                app.beautySliderValueChanged(event);

            whiteDesc = uilabel(whiteGrid);
            whiteDesc.Text = '肤色均匀提亮，避免假白与偏色失真';
            gui_helpers.GuiTheme.applyLabelStyle(whiteDesc, 'muted');

            % 3. 视频模式专属：时域平滑防闪烁开关
            app.DeflickerCheckBox = uicheckbox(sideGrid);
            app.DeflickerCheckBox.Text = '启用视频时域防闪烁 (Deflicker)';
            app.DeflickerCheckBox.FontColor = gui_helpers.GuiTheme.TextHighlight;
            app.DeflickerCheckBox.Value = true;
            app.DeflickerCheckBox.Visible = 'off';

            % 4. 一键美颜按钮
            app.OneClickBeautyButton = uibutton(sideGrid, 'push');
            app.OneClickBeautyButton.Text = '一键美颜 (One-click Beauty)';
            gui_helpers.GuiTheme.applyButtonStyle(app.OneClickBeautyButton, 'primary');
            app.OneClickBeautyButton.Enable = 'off';
            app.OneClickBeautyButton.ButtonPushedFcn = @(~, event) ...
                app.oneClickBeautyButtonPushed(event);

            % 5. 重置原图按钮
            app.ResetBeautyButton = uibutton(sideGrid, 'push');
            app.ResetBeautyButton.Text = '重置原图 (Reset Original)';
            gui_helpers.GuiTheme.applyButtonStyle(app.ResetBeautyButton, 'secondary');
            app.ResetBeautyButton.Enable = 'off';
            app.ResetBeautyButton.ButtonPushedFcn = @(~, event) ...
                app.resetBeautyButtonPushed(event);
        end

        function createStatusBar(app, parentGrid)
            statusBarPanel = uipanel(parentGrid);
            gui_helpers.GuiTheme.applySubPanelStyle(statusBarPanel);
            statusBarPanel.Layout.Row = 3;
            statusBarPanel.Layout.Column = 1;

            statusGrid = uigridlayout(statusBarPanel, [1, 2]);
            gui_helpers.GuiTheme.applyGridLayout(statusGrid, gui_helpers.GuiTheme.BgCardSub);
            statusGrid.RowHeight = {'fit'};
            statusGrid.ColumnWidth = {'1x', 'fit'};
            statusGrid.Padding = [8, 3, 8, 3];

            app.StatusLabel = uilabel(statusGrid);
            app.StatusLabel.Text = 'Open a uint8 RGB JPG or PNG image.';
            app.StatusLabel.HorizontalAlignment = 'left';
            gui_helpers.GuiTheme.applyLabelStyle(app.StatusLabel, 'primary');

            techLabel = uilabel(statusGrid);
            techLabel.Text = 'MATLAB R2024a App Designer';
            gui_helpers.GuiTheme.applyLabelStyle(techLabel, 'muted');
        end
    end

    methods (Access = public)
        function app = faceDetectionApp
            % 构造函数负责注册算法路径、创建并注册 GUI。
            ensureSourcePath(app)
            createComponents(app)
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        function onVideoFrameChanged(app, frameIndex)
            % 响应视频帧改变事件
            app.VideoTimecodeLabel.Text = app.videoHook.formatTimecode(frameIndex);
            app.VideoFrameLabel.Text = sprintf('帧: %d / %d', frameIndex, app.videoHook.TotalFrames);
            app.VideoTimelineSlider.Value = frameIndex;
            if ~isempty(app.videoHook.VideoReaderObj) && isvalid(app.videoHook.VideoReaderObj)
                try
                    app.videoHook.VideoReaderObj.CurrentTime = max(0, (frameIndex - 1) / app.videoHook.FrameRate);
                    frame = readFrame(app.videoHook.VideoReaderObj);
                    app.showImage(app.SourceAxes, frame, 'Video Raw Frame (视频原帧)');
                    app.showImage(app.DetectedAxes, frame, 'Video Beautified (时域美颜效果)');
                catch
                end
            end
        end

        function switchMode(app, targetMode)
            % 切换单图美颜与视频美颜工作模式
            app.CurrentMode = targetMode;
            if strcmp(targetMode, 'image')
                app.SingleImageModeButton.BackgroundColor = gui_helpers.GuiTheme.BtnActiveBg;
                app.SingleImageModeButton.FontColor = [1, 1, 1];
                app.VideoModeButton.BackgroundColor = gui_helpers.GuiTheme.BtnSecondaryBg;
                app.VideoModeButton.FontColor = gui_helpers.GuiTheme.TextMuted;

                app.OpenImageButton.Visible = 'on';
                app.SaveImageButton.Visible = 'on';
                app.OpenVideoButton.Visible = 'off';
                app.ExportVideoButton.Visible = 'off';

                app.VideoToolbar.Visible = 'off';
                app.DeflickerCheckBox.Visible = 'off';
                title(app.SourceAxes, 'Original Image (输入原图)');
                title(app.DetectedAxes, 'Beauty Preview (效果实时预览)');
                app.StatusLabel.Text = '单图模式就绪：请打开 uint8 RGB 格式的 JPG 或 PNG 图像。';
            else
                app.SingleImageModeButton.BackgroundColor = gui_helpers.GuiTheme.BtnSecondaryBg;
                app.SingleImageModeButton.FontColor = gui_helpers.GuiTheme.TextMuted;
                app.VideoModeButton.BackgroundColor = gui_helpers.GuiTheme.BtnActiveBg;
                app.VideoModeButton.FontColor = [1, 1, 1];

                app.OpenImageButton.Visible = 'off';
                app.SaveImageButton.Visible = 'off';
                app.OpenVideoButton.Visible = 'on';
                app.ExportVideoButton.Visible = 'on';

                app.VideoToolbar.Visible = 'on';
                app.DeflickerCheckBox.Visible = 'on';
                title(app.SourceAxes, 'Video Raw Frame (视频原帧)');
                title(app.DetectedAxes, 'Video Beautified (时域美颜效果)');
                app.StatusLabel.Text = '视频模式就绪：支持打开视频并进行逐帧流式美颜与时域防闪烁预览。';
            end
        end

        function openImageFile(app, filePath)
            % 供无交互或测试自动化的图像打开入口。
            if ~(ischar(filePath) && size(filePath, 1) == 1) && ...
                    ~(isstring(filePath) && isscalar(filePath))
                error('faceDetectionApp:InvalidInputPath', ...
                    '文件路径必须是字符向量或字符串标量。');
            end
            filePath = char(filePath);
            if ~isfile(filePath)
                error('faceDetectionApp:OpenImageFailed', ...
                    '指定的文件不存在: %s', filePath);
            end
            app.openImageFromPath(filePath);
            if isempty(app.sourceImage)
                error('faceDetectionApp:OpenImageFailed', ...
                    '未能成功加载图像: %s', filePath);
            end
        end

        function setBeautyParameters(app, smoothing, whitening)
            % 供无交互或测试自动化的参数设置入口。
            if ~isnumeric(smoothing) || ~isscalar(smoothing) || ...
                    ~isnumeric(whitening) || ~isscalar(whitening) || ...
                    smoothing < 0 || smoothing > 100 || ...
                    whitening < 0 || whitening > 100
                error('faceDetectionApp:InvalidBeautyParameters', ...
                    '磨皮和美白参数必须是 [0, 100] 之间的标量数值。');
            end
            if ~app.hasSingleFace || isempty(app.sourceImage)
                error('faceDetectionApp:NoBeautyResult', ...
                    '设置参数前必须先打开包含可识别人脸的图像。');
            end

            app.SmoothingSlider.Value = double(smoothing);
            app.WhiteningSlider.Value = double(whitening);
            app.SmoothingValueLabel.Text = sprintf('Smoothing: %d', round(smoothing));
            app.WhiteningValueLabel.Text = sprintf('Whitening: %d', round(whitening));
            app.updateBeautyPreview();
        end

        function applyOneClickBeauty(app)
            % 应用一键美颜推荐默认参数。
            if ~app.hasSingleFace || isempty(app.sourceImage)
                error('faceDetectionApp:NoBeautyResult', ...
                    '应用一键美颜前必须先打开包含可识别人脸的图像。');
            end
            app.setBeautyParameters(25, 15);
            app.StatusLabel.Text = 'Applied one-click beauty recommendations.';
        end

        function resetBeauty(app)
            % 重置美颜参数与预览画面。
            if ~app.hasSingleFace || isempty(app.sourceImage)
                error('faceDetectionApp:NoBeautyResult', ...
                    '重置前必须先打开包含可识别人脸的图像。');
            end
            app.setBeautyParameters(0, 0);
            app.showImage(app.DetectedAxes, app.sourceImage, 'Original Image (重置原图)');
            app.StatusLabel.Text = 'Reset beauty parameters to original image.';
        end

        function saveImageFile(app, outputPath)
            % 供无交互或测试自动化的保存入口。
            app.saveImageToPath(outputPath);
        end

        function delete(app)
            % 析构时清理组件与定时器资源
            if ~isempty(app.videoHook)
                delete(app.videoHook);
            end
            delete(app.UIFigure);
        end
    end
end
