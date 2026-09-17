classdef faceDetectionApp < matlab.apps.AppBase
    %FACEDETECTIONAPP 主脸美颜 GUI，负责加载、预览、评价和保存结果。

    properties (Access = public)
        % App Designer 兼容的 UI 组件句柄。
        UIFigure matlab.ui.Figure
        OpenImageButton matlab.ui.control.Button
        SaveImageButton matlab.ui.control.Button
        OneClickBeautyButton matlab.ui.control.Button
        ResetBeautyButton matlab.ui.control.Button
        SmoothingSlider matlab.ui.control.Slider
        WhiteningSlider matlab.ui.control.Slider
        SmoothingValueLabel matlab.ui.control.Label
        WhiteningValueLabel matlab.ui.control.Label
        MetricsPanel matlab.ui.container.Panel
        EntropyLabel matlab.ui.control.Label
        StandardDeviationLabel matlab.ui.control.Label
        AverageGradientLabel matlab.ui.control.Label
        ElapsedTimeLabel matlab.ui.control.Label
        SourceAxes matlab.ui.control.UIAxes
        DetectedAxes matlab.ui.control.UIAxes
        StatusLabel matlab.ui.control.Label
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
        end

        function openImageButtonPushed(app, ~)
            % 打开图像并立即执行主脸检测。
            [fileName, folderPath] = uigetfile( ...
                {'*.jpg;*.jpeg;*.png', 'JPG and PNG Images (*.jpg, *.jpeg, *.png)'}, ...
                'Open Image');
            if isequal(fileName, 0)
                return;
            end
            app.openImageFromPath(fullfile(folderPath, fileName));
        end

        function openImageFromPath(app, filePath)
            % 由按钮和可重复的 GUI 回归共同调用的打开流程。
            try
                inputImage = imread(filePath);
                imageInfo = imfinfo(filePath);
            catch exception
                app.clearLoadedImage();
                uialert(app.UIFigure, exception.message, 'Unable to Open Image');
                return;
            end

            % MVP 只接受 uint8 三通道 RGB 图像，不静默转换其他位深。
            if ~isa(inputImage, 'uint8') || ndims(inputImage) ~= 3 || ...
                    size(inputImage, 3) ~= 3
                app.clearLoadedImage();
                uialert(app.UIFigure, ...
                    'Only uint8 three-channel RGB JPG and PNG images are supported.', ...
                    'Unsupported Image');
                return;
            end

            % 新图像进入检测前先清理旧的结果和保存状态。
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
            app.inputFormat = app.normalizedFormat(extension);
            app.showImage(app.SourceAxes, inputImage, 'Original Image');
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
                uialert(app.UIFigure, exception.message, 'Face Detection Failed');
                return;
            end

            if ~isSingleFace
                app.clearDetectionResult();
                uialert(app.UIFigure, ...
                    'No recognizable foreground face was found. Please choose another image.', ...
                    'Face Detection Failed');
                return;
            end

            app.StatusLabel.Text = 'Analyzing skin and facial features...';
            drawnow;
            try
                app.previewFaceBox = detectedFaceBox;
                app.faceBox = app.scaleFaceBox(detectedFaceBox, ...
                    1 / app.previewScale, size(app.sourceImage));
                preparedContext = prepareBeautyContext( ...
                    app.previewImage, app.previewFaceBox, ...
                    detectionDetails.selectedParsing, ...
                    struct('rotationDegrees', ...
                    detectionDetails.orientationDegrees));
                app.previewContext = normalizeBeautyContext( ...
                    app.previewImage, app.previewFaceBox, preparedContext);
                app.beautyContext = app.previewContext;
            catch exception
                app.clearDetectionResult();
                uialert(app.UIFigure, exception.message, 'Beauty Analysis Failed');
                return;
            end
            app.hasSingleFace = true;
            app.SmoothingSlider.Value = 25;
            app.WhiteningSlider.Value = 15;
            app.updateStrengthLabels();
            app.setBeautyControlsEnabled(true);
            app.refreshPreview(25, 15, true);
        end

        function beautySliderValueChanging(app, event, isSmoothing)
            % 拖动时节流，避免每个鼠标事件都重复执行完整算法。
            if ~isempty(app.previewClock) && toc(app.previewClock) < 0.2
                return;
            end
            if isSmoothing
                smoothingStrength = event.Value;
                whiteningStrength = app.WhiteningSlider.Value;
            else
                smoothingStrength = app.SmoothingSlider.Value;
                whiteningStrength = event.Value;
            end
            app.refreshPreview(smoothingStrength, whiteningStrength, false);
            if app.hasSingleFace
                app.updateStrengthLabels(smoothingStrength, whiteningStrength);
                app.previewClock = tic;
            end
        end

        function beautySliderValueChanged(app, ~)
            % 松开滑块后强制完成一次最终刷新。
            app.refreshPreview(app.SmoothingSlider.Value, app.WhiteningSlider.Value, true);
            if app.hasSingleFace
                app.previewClock = tic;
            end
        end

        function oneClickBeautyButtonPushed(app, ~)
            % 一键美颜只推荐参数，实际处理仍复用普通预览流程。
            if ~app.hasSingleFace
                return;
            end
            try
                params = recommendBeautyParams( ...
                    app.previewImage, app.previewFaceBox, app.previewContext);
                app.SmoothingSlider.Value = params.smoothingStrength;
                app.WhiteningSlider.Value = params.whiteningStrength;
                app.updateStrengthLabels();
                app.refreshPreview(params.smoothingStrength, params.whiteningStrength, true);
                if app.hasSingleFace
                    app.previewClock = tic;
                end
            catch exception
                app.clearDetectionResult();
                uialert(app.UIFigure, exception.message, 'Beauty Preview Failed');
            end
        end

        function resetBeautyButtonPushed(app, ~)
            % 重置后直接显示原图，不伪造美颜处理耗时。
            if ~app.hasSingleFace
                return;
            end
            app.SmoothingSlider.Value = 0;
            app.WhiteningSlider.Value = 0;
            app.updateStrengthLabels();
            try
                app.beautifiedImage = app.sourceImage;
                app.currentMetrics = evaluateImage( ...
                    app.sourceImage, app.sourceImage, 0);
                app.showImage(app.DetectedAxes, app.beautifiedImage, 'Beauty Preview');
                app.updateMetrics(app.currentMetrics);
                app.previewClock = tic;
                app.StatusLabel.Text = 'Original image restored.';
            catch exception
                app.clearDetectionResult();
                uialert(app.UIFigure, exception.message, 'Reset Failed');
            end
        end

        function refreshPreview(app, smoothingStrength, whiteningStrength, updateMetrics)
            % 只将一次 beautifyImage 调用包在耗时统计中。
            if nargin < 4, updateMetrics = true; end
            if ~app.hasSingleFace || isempty(app.sourceImage)
                return;
            end
            params = struct( ...
                'smoothingStrength', smoothingStrength, ...
                'whiteningStrength', whiteningStrength);
            try
                startTime = tic;
                [outputImage, processingDiagnostics] = beautifyImage( ...
                    app.previewImage, params, app.previewFaceBox, app.previewContext);
                elapsedSeconds = toc(startTime);
                app.lastDiagnostics = processingDiagnostics;
                if updateMetrics
                    metrics = evaluateImage(app.previewImage, outputImage, elapsedSeconds);
                else
                    metrics = [];
                end
            catch exception
                app.clearDetectionResult();
                uialert(app.UIFigure, exception.message, 'Beauty Preview Failed');
                return;
            end

            app.beautifiedImage = outputImage;
            if updateMetrics
                app.currentMetrics = metrics;
            end
            app.updateStrengthLabels(smoothingStrength, whiteningStrength);
            app.showImage(app.DetectedAxes, outputImage, 'Beauty Preview');
            if updateMetrics
                app.updateMetrics(metrics);
            end
            app.previewClock = tic;
            app.StatusLabel.Text = 'Beauty preview updated.';
        end

        function updateStrengthLabels(app, smoothingStrength, whiteningStrength)
            % 同步显示两个滑块的当前强度。
            if nargin < 2
                smoothingStrength = app.SmoothingSlider.Value;
                whiteningStrength = app.WhiteningSlider.Value;
            end
            app.SmoothingValueLabel.Text = sprintf( ...
                'Smoothing: %.0f', smoothingStrength);
            app.WhiteningValueLabel.Text = sprintf( ...
                'Whitening: %.0f', whiteningStrength);
        end

        function updateMetrics(app, metrics)
            % 更新独立指标区域中的四项指标。
            app.EntropyLabel.Text = sprintf('Entropy: %.4f', metrics.entropy);
            app.StandardDeviationLabel.Text = sprintf( ...
                'Standard deviation: %.4f', metrics.standardDeviation);
            app.AverageGradientLabel.Text = sprintf( ...
                'Average gradient: %.4f', metrics.averageGradient);
            app.ElapsedTimeLabel.Text = sprintf( ...
                'Single-image time: %.2f ms', metrics.elapsedSeconds * 1000);
        end

        function saveImageButtonPushed(app, ~)
            % 保存当前美颜结果并读回校验像素属性。
            if ~app.hasSingleFace || isempty(app.beautifiedImage)
                uialert(app.UIFigure, ...
                    'Open an image with a recognizable foreground face before saving.', ...
                    'No Beauty Result');
                return;
            end

            defaultExtension = app.inputFormat;
            if strcmp(defaultExtension, 'jpg') && ...
                    app.hasResolutionMetadata(app.inputImageInfo)
                defaultExtension = 'png';
            end
            defaultName = sprintf('%s_beautified.%s', ...
                app.inputBaseName, defaultExtension);
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
            app.writeImageWithResolution(outputImage, outputPath, ...
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
            sameResolution = app.hasSameResolution( ...
                app.inputImageInfo, outputInfo);
            if ~samePixels || ~sameChannels || ~sameAspectRatio || ...
                    ~sameResolution
                error('faceDetectionApp:SaveVerificationFailed', ...
                    '保存结果的尺寸、通道、比例或分辨率与输入图像不一致。');
            end

            app.StatusLabel.Text = 'Beauty result saved successfully.';
        end

        function clearLoadedImage(app)
            % 清空已加载图像和所有美颜状态。
            app.sourceImage = [];
            app.previewImage = [];
            app.previewFaceBox = zeros(0, 4);
            app.previewContext = [];
            app.previewScale = 1;
            app.inputFormat = '';
            app.inputBaseName = '';
            app.inputImageInfo = [];
            app.lastDiagnostics = [];
            cla(app.SourceAxes);
            title(app.SourceAxes, 'Original Image');
            app.clearDetectionResult();
        end

        function clearDetectionResult(app)
            % 清空结果、指标和 faceBox，并禁止处理旧数据。
            app.beautifiedImage = [];
            app.previewImage = [];
            app.previewFaceBox = zeros(0, 4);
            app.previewContext = [];
            app.previewScale = 1;
            app.faceBox = zeros(0, 4);
            app.beautyContext = [];
            app.currentMetrics = [];
            app.lastDiagnostics = [];
            app.previewClock = [];
            app.hasSingleFace = false;
            if ~isempty(app.SmoothingSlider)
                app.SmoothingSlider.Value = 25;
                app.WhiteningSlider.Value = 15;
                app.updateStrengthLabels();
            end
            app.setBeautyControlsEnabled(false);
            cla(app.DetectedAxes);
            title(app.DetectedAxes, 'Beauty Preview');
            app.EntropyLabel.Text = 'Entropy: --';
            app.StandardDeviationLabel.Text = 'Standard deviation: --';
            app.AverageGradientLabel.Text = 'Average gradient: --';
            app.ElapsedTimeLabel.Text = 'Single-image time: --';
            app.StatusLabel.Text = 'Open a uint8 RGB JPG or PNG image.';
        end

        function setBeautyControlsEnabled(app, isEnabled)
            if isEnabled
                state = 'on';
            else
                state = 'off';
            end
            app.SaveImageButton.Enable = state;
            app.OneClickBeautyButton.Enable = state;
            app.ResetBeautyButton.Enable = state;
            app.SmoothingSlider.Enable = state;
            app.WhiteningSlider.Enable = state;
        end

        function showImage(~, targetAxes, imageData, titleText)
            % 在指定 UIAxes 中按原比例显示图像。
            imageHandle = findobj(targetAxes, 'Type', 'image');
            if ~isempty(imageHandle) && isvalid(imageHandle(1))
                imageHandle(1).CData = imageData;
            else
                cla(targetAxes);
                image(targetAxes, imageData);
            end
            axis(targetAxes, 'image');
            axis(targetAxes, 'off');
            title(targetAxes, titleText, 'Interpreter', 'none');
        end

        function format = normalizedFormat(~, extension)
            % 统一保存格式名称，非 PNG 输入按 JPG 处理。
            if strcmpi(extension, '.png')
                format = 'png';
            else
                format = 'jpg';
            end
        end

        function hasResolution = hasResolutionMetadata(~, imageInfo)
            % 有分辨率元数据时默认选择可携带该元数据的 PNG。
            hasResolution = isstruct(imageInfo) && isscalar(imageInfo) && ...
                all(isfield(imageInfo, {'XResolution', 'YResolution'})) && ...
                isnumeric(imageInfo.XResolution) && ...
                isnumeric(imageInfo.YResolution) && ...
                isscalar(imageInfo.XResolution) && ...
                isscalar(imageInfo.YResolution) && ...
                isfinite(imageInfo.XResolution) && ...
                isfinite(imageInfo.YResolution) && ...
                imageInfo.XResolution > 0 && imageInfo.YResolution > 0;
        end

        function writeImageWithResolution(~, imageData, outputPath, imageInfo)
            % 保存时传递输入文件的像素分辨率元数据。
            options = {};
            [~, ~, extension] = fileparts(outputPath);
            if strcmpi(extension, '.png') && ...
                    isstruct(imageInfo) && isscalar(imageInfo) && ...
                    all(isfield(imageInfo, {'XResolution', 'YResolution'})) && ...
                    isnumeric(imageInfo.XResolution) && ...
                    isnumeric(imageInfo.YResolution) && ...
                    isfinite(imageInfo.XResolution) && ...
                    isfinite(imageInfo.YResolution) && ...
                    imageInfo.XResolution > 0 && imageInfo.YResolution > 0
                resolution = double([imageInfo.XResolution, ...
                    imageInfo.YResolution]);
                resolutionUnit = 'unknown';
                if isfield(imageInfo, 'ResolutionUnit')
                    unit = imageInfo.ResolutionUnit;
                    if isstring(unit) && isscalar(unit)
                        unit = char(unit);
                    end
                    if ischar(unit) && size(unit, 1) == 1
                        unit = lower(strtrim(unit));
                        if strcmp(unit, 'meter')
                            resolutionUnit = 'meter';
                        elseif strcmp(unit, 'inch')
                            resolution = resolution * 39.3700787401575;
                            resolutionUnit = 'meter';
                        elseif strcmp(unit, 'centimeter')
                            resolution = resolution * 100;
                            resolutionUnit = 'meter';
                        end
                    end
                end
                options = {'XResolution', resolution(1), ...
                    'YResolution', resolution(2), ...
                    'ResolutionUnit', resolutionUnit};
            end
            imwrite(imageData, outputPath, options{:});
        end

        function same = hasSameResolution(app, inputInfo, outputInfo)
            % 只有输入文件声明了分辨率时才执行元数据等值校验。
            same = true;
            if ~isstruct(inputInfo) || ~isscalar(inputInfo) || ...
                    ~all(isfield(inputInfo, {'XResolution', 'YResolution'}))
                return;
            end
            if ~isstruct(outputInfo) || ~isscalar(outputInfo) || ...
                    ~all(isfield(outputInfo, {'XResolution', 'YResolution'}))
                same = false;
                return;
            end
            [inputResolution, inputValid] = app.resolutionInMeters(inputInfo);
            [outputResolution, outputValid] = app.resolutionInMeters(outputInfo);
            same = inputValid && outputValid && ...
                all(abs(outputResolution - inputResolution) <= ...
                max(1, abs(inputResolution) * 1e-6));
        end

        function [resolution, valid] = resolutionInMeters(~, imageInfo)
            resolution = double([imageInfo.XResolution, ...
                imageInfo.YResolution]);
            valid = all(isfinite(resolution)) && all(resolution > 0);
            if ~valid || ~isfield(imageInfo, 'ResolutionUnit')
                return;
            end
            unit = imageInfo.ResolutionUnit;
            if isstring(unit) && isscalar(unit)
                unit = char(unit);
            end
            if ~ischar(unit) || size(unit, 1) ~= 1
                valid = false;
                return;
            end
            switch lower(strtrim(unit))
                case 'meter'
                case 'inch'
                    resolution = resolution * 39.3700787401575;
                case 'centimeter'
                    resolution = resolution * 100;
                otherwise
                    % unknown 单位只能比较原始数值，不能进行物理换算。
            end
        end

        function createComponents(app)
            % 创建 GUI 组件并设置双栏图像布局。
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100, 100, 1200, 760];
            app.UIFigure.Name = 'Portrait Beauty';

            mainGrid = uigridlayout(app.UIFigure, [4, 2]);
            mainGrid.RowHeight = {'fit', '1x', 'fit', 'fit'};
            mainGrid.ColumnWidth = {'1x', '1x'};
            mainGrid.Padding = [12, 12, 12, 12];

            controlsGrid = uigridlayout(mainGrid, [2, 6]);
            controlsGrid.Layout.Row = 1;
            controlsGrid.Layout.Column = [1, 2];
            controlsGrid.RowHeight = {'fit', 'fit'};
            controlsGrid.ColumnWidth = {'fit', 'fit', 'fit', 'fit', '1x', '1x'};

            app.OpenImageButton = uibutton(controlsGrid, 'push');
            app.OpenImageButton.Text = 'Open Image';
            app.OpenImageButton.Layout.Row = 1;
            app.OpenImageButton.Layout.Column = 1;
            app.OpenImageButton.ButtonPushedFcn = @(~, event) ...
                app.openImageButtonPushed(event);

            app.OneClickBeautyButton = uibutton(controlsGrid, 'push');
            app.OneClickBeautyButton.Text = 'One-click Beauty';
            app.OneClickBeautyButton.Layout.Row = 1;
            app.OneClickBeautyButton.Layout.Column = 2;
            app.OneClickBeautyButton.Enable = 'off';
            app.OneClickBeautyButton.ButtonPushedFcn = @(~, event) ...
                app.oneClickBeautyButtonPushed(event);

            app.ResetBeautyButton = uibutton(controlsGrid, 'push');
            app.ResetBeautyButton.Text = 'Reset Original';
            app.ResetBeautyButton.Layout.Row = 1;
            app.ResetBeautyButton.Layout.Column = 3;
            app.ResetBeautyButton.Enable = 'off';
            app.ResetBeautyButton.ButtonPushedFcn = @(~, event) ...
                app.resetBeautyButtonPushed(event);

            app.SmoothingValueLabel = uilabel(controlsGrid);
            app.SmoothingValueLabel.Text = 'Smoothing: 25';
            app.SmoothingValueLabel.Layout.Row = 2;
            app.SmoothingValueLabel.Layout.Column = 1;
            app.SmoothingSlider = uislider(controlsGrid);
            app.SmoothingSlider.Limits = [0, 100];
            app.SmoothingSlider.Value = 25;
            app.SmoothingSlider.MajorTicks = 0:20:100;
            app.SmoothingSlider.Layout.Row = 2;
            app.SmoothingSlider.Layout.Column = [2, 3];
            app.SmoothingSlider.Enable = 'off';
            app.SmoothingSlider.ValueChangingFcn = @(~, event) ...
                app.beautySliderValueChanging(event, true);
            app.SmoothingSlider.ValueChangedFcn = @(~, event) ...
                app.beautySliderValueChanged(event);

            app.WhiteningValueLabel = uilabel(controlsGrid);
            app.WhiteningValueLabel.Text = 'Whitening: 15';
            app.WhiteningValueLabel.Layout.Row = 2;
            app.WhiteningValueLabel.Layout.Column = 4;
            app.WhiteningSlider = uislider(controlsGrid);
            app.WhiteningSlider.Limits = [0, 100];
            app.WhiteningSlider.Value = 15;
            app.WhiteningSlider.MajorTicks = 0:20:100;
            app.WhiteningSlider.Layout.Row = 2;
            app.WhiteningSlider.Layout.Column = [5, 6];
            app.WhiteningSlider.Enable = 'off';
            app.WhiteningSlider.ValueChangingFcn = @(~, event) ...
                app.beautySliderValueChanging(event, false);
            app.WhiteningSlider.ValueChangedFcn = @(~, event) ...
                app.beautySliderValueChanged(event);

            app.SaveImageButton = uibutton(controlsGrid, 'push');
            app.SaveImageButton.Text = 'Save Image';
            app.SaveImageButton.Layout.Row = 1;
            app.SaveImageButton.Layout.Column = [5, 6];
            app.SaveImageButton.Enable = 'off';
            app.SaveImageButton.ButtonPushedFcn = @(~, event) ...
                app.saveImageButtonPushed(event);

            app.SourceAxes = uiaxes(mainGrid);
            app.SourceAxes.Layout.Row = 2;
            app.SourceAxes.Layout.Column = 1;
            title(app.SourceAxes, 'Original Image');
            axis(app.SourceAxes, 'off');

            app.DetectedAxes = uiaxes(mainGrid);
            app.DetectedAxes.Layout.Row = 2;
            app.DetectedAxes.Layout.Column = 2;
            title(app.DetectedAxes, 'Beauty Preview');
            axis(app.DetectedAxes, 'off');

            app.MetricsPanel = uipanel(mainGrid);
            app.MetricsPanel.Title = 'Current Metrics';
            app.MetricsPanel.Layout.Row = 3;
            app.MetricsPanel.Layout.Column = [1, 2];
            metricsGrid = uigridlayout(app.MetricsPanel, [1, 4]);
            metricsGrid.ColumnWidth = {'1x', '1x', '1x', '1x'};
            app.EntropyLabel = uilabel(metricsGrid);
            app.EntropyLabel.Text = 'Entropy: --';
            app.EntropyLabel.HorizontalAlignment = 'center';
            app.StandardDeviationLabel = uilabel(metricsGrid);
            app.StandardDeviationLabel.Text = 'Standard deviation: --';
            app.StandardDeviationLabel.HorizontalAlignment = 'center';
            app.AverageGradientLabel = uilabel(metricsGrid);
            app.AverageGradientLabel.Text = 'Average gradient: --';
            app.AverageGradientLabel.HorizontalAlignment = 'center';
            app.ElapsedTimeLabel = uilabel(metricsGrid);
            app.ElapsedTimeLabel.Text = 'Single-image time: --';
            app.ElapsedTimeLabel.HorizontalAlignment = 'center';

            app.StatusLabel = uilabel(mainGrid);
            app.StatusLabel.Text = 'Open a uint8 RGB JPG or PNG image.';
            app.StatusLabel.HorizontalAlignment = 'center';
            app.StatusLabel.Layout.Row = 4;
            app.StatusLabel.Layout.Column = [1, 2];

            app.UIFigure.Visible = 'on';
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

        function openImageFile(app, filePath)
            % 按路径执行与“打开图像”按钮相同的完整流程。
            if ~(ischar(filePath) && size(filePath, 1) == 1) && ...
                    ~(isstring(filePath) && isscalar(filePath))
                error('faceDetectionApp:InvalidInputPath', ...
                    '输入路径必须是字符向量或字符串标量。');
            end
            app.openImageFromPath(char(filePath));
            if ~app.hasSingleFace
                error('faceDetectionApp:OpenImageFailed', ...
                    '图像未能完成单人脸分析。');
            end
        end

        function setBeautyParameters(app, smoothingStrength, whiteningStrength)
            % 设置两个滑块并强制执行一次实时预览。
            values = [smoothingStrength, whiteningStrength];
            if ~isnumeric(values) || ~isreal(values) || ...
                    any(~isfinite(values)) || any(values < 0) || ...
                    any(values > 100)
                error('faceDetectionApp:InvalidBeautyParameters', ...
                    '美颜强度必须是 0 到 100 内的有限数值。');
            end
            if ~app.hasSingleFace
                error('faceDetectionApp:NoBeautyResult', ...
                    '设置参数前必须先打开图像。');
            end
            app.SmoothingSlider.Value = smoothingStrength;
            app.WhiteningSlider.Value = whiteningStrength;
            app.updateStrengthLabels();
            app.refreshPreview(smoothingStrength, whiteningStrength, true);
        end

        function applyOneClickBeauty(app)
            % 执行与“一键美颜”按钮相同的推荐和预览流程。
            if ~app.hasSingleFace
                error('faceDetectionApp:NoBeautyResult', ...
                    '一键美颜前必须先打开图像。');
            end
            app.oneClickBeautyButtonPushed([]);
        end

        function resetBeauty(app)
            % 执行与“重置原图”按钮相同的严格原图恢复流程。
            if ~app.hasSingleFace
                error('faceDetectionApp:NoBeautyResult', ...
                    '重置前必须先打开图像。');
            end
            app.resetBeautyButtonPushed([]);
        end

        function saveImageFile(app, outputPath)
            % 按路径执行与“保存图像”按钮相同的原尺寸保存流程。
            app.saveImageToPath(outputPath);
        end

        function delete(app)
            % 删除 App 时同步释放 UIFigure。
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure)
            end
        end
    end
end
