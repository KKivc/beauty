classdef faceDetectionApp < matlab.apps.AppBase
    %FACEDETECTIONAPP 单人脸检测 GUI，负责加载、显示和保存检测结果。

    properties (Access = public)
        % App Designer 兼容的 UI 组件句柄。
        UIFigure matlab.ui.Figure
        OpenImageButton matlab.ui.control.Button
        SaveImageButton matlab.ui.control.Button
        SourceAxes matlab.ui.control.UIAxes
        DetectedAxes matlab.ui.control.UIAxes
        StatusLabel matlab.ui.control.Label
    end

    properties (Access = private)
        % 缓存原始图像与检测结果，保存时用于尺寸校验。
        sourceImage = []
        detectedImage = []

        % 记录输入文件信息，用于生成默认输出文件名。
        inputFormat = ''
        inputBaseName = ''

        % 标记当前是否已有且仅有一个 face detection 结果。
        hasSingleFace = false
    end

    methods (Access = private)
        function openImageButtonPushed(app, ~)
            % 打开图像并立即执行单人脸检测。
            [fileName, folderPath] = uigetfile( ...
                {'*.jpg;*.jpeg;*.png', 'JPG and PNG Images (*.jpg, *.jpeg, *.png)'}, ...
                'Open Image');

            if isequal(fileName, 0)
                return;
            end

            % 读取用户选择的 JPG 或 PNG 文件。
            filePath = fullfile(folderPath, fileName);
            try
                inputImage = imread(filePath);
            catch exception
                uialert(app.UIFigure, exception.message, 'Unable to Open Image');
                return;
            end

            % 当前流程只支持三通道 RGB 图像。
            if ndims(inputImage) ~= 3 || size(inputImage, 3) ~= 3
                app.clearLoadedImage();
                uialert(app.UIFigure, ...
                    'Only three-channel RGB JPG and PNG images are supported.', ...
                    'Unsupported Image');
                return;
            end

            % 缓存输入信息，并先在左侧 Axes 展示原图。
            [~, baseName, extension] = fileparts(fileName);
            app.sourceImage = inputImage;
            app.inputBaseName = baseName;
            app.inputFormat = app.normalizedFormat(extension);
            app.showImage(app.SourceAxes, inputImage, 'Original Image');
            app.clearDetectionResult();
            app.StatusLabel.Text = 'Detecting face...';
            drawnow;

            % 调用算法层函数检测 faceBox。
            try
                [faceBox, isSingleFace] = detectSingleFace(inputImage);
            catch exception
                app.clearDetectionResult();
                uialert(app.UIFigure, exception.message, 'Face Detection Failed');
                return;
            end

            % 未检测到人脸或检测到多张人脸时，不允许保存结果。
            if ~isSingleFace
                app.clearDetectionResult();
                uialert(app.UIFigure, ...
                    'Please choose an image containing exactly one face.', ...
                    'Single Face Required');
                return;
            end

            % 将检测框绘制到结果图，并启用保存按钮。
            app.detectedImage = annotateFaceDetection(inputImage, faceBox);
            app.hasSingleFace = true;
            app.SaveImageButton.Enable = 'on';
            app.showImage(app.DetectedAxes, app.detectedImage, 'Detected Face');
            app.StatusLabel.Text = 'One face detected. You can save the result.';
        end

        function saveImageButtonPushed(app, ~)
            % 保存带人脸检测框的图像。
            if ~app.hasSingleFace
                uialert(app.UIFigure, ...
                    'Open an image with exactly one detected face before saving.', ...
                    'No Detection Result');
                return;
            end

            % 默认沿用输入文件名和格式，便于用户识别结果文件。
            defaultName = sprintf('%s_detected.%s', ...
                app.inputBaseName, app.inputFormat);
            [fileName, folderPath, filterIndex] = uiputfile( ...
                {'*.jpg', 'JPEG Image (*.jpg)'; '*.png', 'PNG Image (*.png)'}, ...
                'Save Detection Result', defaultName);

            if isequal(fileName, 0)
                return;
            end

            % 用户未输入扩展名时，根据 uiputfile 过滤器补全格式。
            [~, outputBaseName, extension] = fileparts(fileName);
            if isempty(extension)
                if filterIndex == 1
                    extension = '.jpg';
                else
                    extension = '.png';
                end
            end
            outputPath = fullfile(folderPath, [outputBaseName, extension]);

            % 写入后重新读取，确认保存结果仍保持输入图像尺寸。
            try
                imwrite(app.detectedImage, outputPath);
                outputImage = imread(outputPath);
            catch exception
                uialert(app.UIFigure, exception.message, 'Unable to Save Image');
                return;
            end

            if size(outputImage, 1) ~= size(app.sourceImage, 1) || ...
                    size(outputImage, 2) ~= size(app.sourceImage, 2)
                uialert(app.UIFigure, ...
                    'The saved image dimensions do not match the input image.', ...
                    'Save Verification Failed');
                return;
            end

            app.StatusLabel.Text = 'Detection result saved successfully.';
        end

        function clearLoadedImage(app)
            % 清空已加载图像和所有检测状态。
            app.sourceImage = [];
            app.inputFormat = '';
            app.inputBaseName = '';
            cla(app.SourceAxes);
            title(app.SourceAxes, 'Original Image');
            app.clearDetectionResult();
        end

        function clearDetectionResult(app)
            % 重置右侧结果区域，并禁止保存旧结果。
            app.detectedImage = [];
            app.hasSingleFace = false;
            app.SaveImageButton.Enable = 'off';
            cla(app.DetectedAxes);
            title(app.DetectedAxes, 'Detection Result');
            app.StatusLabel.Text = 'Open a JPG or PNG image to detect one face.';
        end

        function showImage(~, targetAxes, imageData, titleText)
            % 在指定 UIAxes 中按原比例显示图像。
            cla(targetAxes);
            image(targetAxes, imageData);
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

        function createComponents(app)
            % 创建 GUI 组件并设置双栏图像布局。
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100, 100, 1200, 700];
            app.UIFigure.Name = 'Single Face Detection';

            % 三行两列：顶部按钮，中间原图和结果图，底部状态提示。
            grid = uigridlayout(app.UIFigure, [3, 2]);
            grid.RowHeight = {'fit', '1x', 'fit'};
            grid.ColumnWidth = {'1x', '1x'};
            grid.Padding = [12, 12, 12, 12];

            % 打开图像按钮。
            app.OpenImageButton = uibutton(grid, 'push');
            app.OpenImageButton.Text = 'Open Image';
            app.OpenImageButton.Layout.Row = 1;
            app.OpenImageButton.Layout.Column = 1;
            app.OpenImageButton.ButtonPushedFcn = @(~, event) app.openImageButtonPushed(event);

            % 保存按钮默认禁用，检测到单张人脸后再启用。
            app.SaveImageButton = uibutton(grid, 'push');
            app.SaveImageButton.Text = 'Save Image';
            app.SaveImageButton.Enable = 'off';
            app.SaveImageButton.Layout.Row = 1;
            app.SaveImageButton.Layout.Column = 2;
            app.SaveImageButton.ButtonPushedFcn = @(~, event) app.saveImageButtonPushed(event);

            % 左侧 Axes 显示原始图像。
            app.SourceAxes = uiaxes(grid);
            app.SourceAxes.Layout.Row = 2;
            app.SourceAxes.Layout.Column = 1;
            title(app.SourceAxes, 'Original Image');
            axis(app.SourceAxes, 'off');

            % 右侧 Axes 显示带 Rectangle 的检测结果。
            app.DetectedAxes = uiaxes(grid);
            app.DetectedAxes.Layout.Row = 2;
            app.DetectedAxes.Layout.Column = 2;
            title(app.DetectedAxes, 'Detection Result');
            axis(app.DetectedAxes, 'off');

            % 底部 Label 显示当前操作状态。
            app.StatusLabel = uilabel(grid);
            app.StatusLabel.Text = 'Open a JPG or PNG image to detect one face.';
            app.StatusLabel.HorizontalAlignment = 'center';
            app.StatusLabel.Layout.Row = 3;
            app.StatusLabel.Layout.Column = [1, 2];

            app.UIFigure.Visible = 'on';
        end
    end

    methods (Access = public)
        function app = faceDetectionApp
            % 构造函数负责创建并注册 GUI。
            createComponents(app)
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        function delete(app)
            % 删除 App 时同步释放 UIFigure。
            delete(app.UIFigure)
        end
    end
end
