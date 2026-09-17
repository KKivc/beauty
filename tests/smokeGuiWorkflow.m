function result = smokeGuiWorkflow(inputPath, outputPath)
%SMOKEGUIWORKFLOW 在 MATLAB 中回归 GUI 的打开、预览、重置和保存流程。
%   使用公开的按路径接口驱动现有按钮逻辑，避免文件对话框阻断批处理；
%   不改变 GUI 的交互入口，输出文件由调用方指定并可直接查看。

projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot, 'src'));
addpath(fullfile(projectRoot, 'gui'));
if nargin < 1 || isempty(inputPath) || ~isfile(inputPath)
    error('smokeGuiWorkflow:InvalidInput', ...
        '必须提供存在的真实人像输入文件。');
end
if nargin < 2 || isempty(outputPath)
    outputPath = fullfile(tempdir, 'image_beauty_gui_workflow.png');
end

inputImage = imread(inputPath);
inputInfo = imfinfo(inputPath);
validateRgbImage(inputImage);

app = faceDetectionApp();
cleanup = onCleanup(@() delete(app)); %#ok<NASGU>
app.openImageFile(inputPath);

sourceDisplayed = readAxesImage(app.SourceAxes, ...
    'smokeGuiWorkflow:MissingSourceImage');
previewDisplayed = readAxesImage(app.DetectedAxes, ...
    'smokeGuiWorkflow:MissingPreviewImage');
initialPreviewSize = size(previewDisplayed);
initialSourceMatch = isequal(sourceDisplayed, inputImage);
initialControlsEnabled = strcmp(app.SaveImageButton.Enable, 'on') && ...
    strcmp(app.OneClickBeautyButton.Enable, 'on') && ...
    strcmp(app.ResetBeautyButton.Enable, 'on');

app.setBeautyParameters(50, 25);
parameterPreview = readAxesImage(app.DetectedAxes, ...
    'smokeGuiWorkflow:MissingParameterPreview');
metricsVisible = ~contains(app.EntropyLabel.Text, '--') && ...
    ~contains(app.StandardDeviationLabel.Text, '--') && ...
    ~contains(app.AverageGradientLabel.Text, '--') && ...
    ~contains(app.ElapsedTimeLabel.Text, '--');
parameterPreviewChanged = ~isequal(parameterPreview, previewDisplayed);

app.applyOneClickBeauty();
oneClickPreview = readAxesImage(app.DetectedAxes, ...
    'smokeGuiWorkflow:MissingOneClickPreview');
oneClickParameters = [app.SmoothingSlider.Value, app.WhiteningSlider.Value];
oneClickValid = all(isfinite(oneClickParameters)) && ...
    all(oneClickParameters >= 0) && all(oneClickParameters <= 100) && ...
    ~isempty(oneClickPreview);

app.resetBeauty();
resetDisplayed = readAxesImage(app.DetectedAxes, ...
    'smokeGuiWorkflow:MissingResetImage');
resetExact = isequal(resetDisplayed, inputImage) && ...
    app.SmoothingSlider.Value == 0 && app.WhiteningSlider.Value == 0;

app.setBeautyParameters(25, 15);
app.saveImageFile(outputPath);
savedImage = imread(outputPath);
savedInfo = imfinfo(outputPath);
savedSize = size(savedImage);
sameSize = isequal(savedSize, size(inputImage));
sameChannels = ndims(savedImage) == 3 && size(savedImage, 3) == 3;
sameAspectRatio = savedSize(2) * size(inputImage, 1) == ...
    size(inputImage, 2) * savedSize(1);
sameResolution = hasSameResolution(inputInfo, savedInfo);

result = struct( ...
    'passed', initialSourceMatch && initialControlsEnabled && ...
    parameterPreviewChanged && metricsVisible && oneClickValid && ...
    resetExact && sameSize && sameChannels && sameAspectRatio && ...
    sameResolution, ...
    'initialPreviewSize', initialPreviewSize, ...
    'parameterPreviewChanged', parameterPreviewChanged, ...
    'metricsVisible', metricsVisible, ...
    'oneClickParameters', oneClickParameters, ...
    'resetExact', resetExact, ...
    'savedSize', savedSize, ...
    'sameAspectRatio', sameAspectRatio, ...
    'sameResolution', sameResolution, ...
    'outputPath', outputPath);
if ~result.passed
    error('smokeGuiWorkflow:VerificationFailed', ...
        'GUI 流程或原尺寸保存校验失败。');
end
end

function imageData = readAxesImage(axesHandle, identifier)
imageHandle = findobj(axesHandle, 'Type', 'image');
if isempty(imageHandle) || ~isvalid(imageHandle(1))
    error(identifier, '指定坐标区没有可读的图像结果。');
end
imageData = imageHandle(1).CData;
end

function same = hasSameResolution(inputInfo, outputInfo)
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
[inputResolution, inputValid] = resolutionInMeters(inputInfo);
[outputResolution, outputValid] = resolutionInMeters(outputInfo);
same = inputValid && outputValid && ...
    all(abs(outputResolution - inputResolution) <= ...
    max(1, abs(inputResolution) * 1e-6));
end

function [resolution, valid] = resolutionInMeters(info)
resolution = double([info.XResolution, info.YResolution]);
valid = all(isfinite(resolution)) && all(resolution > 0);
if ~valid || ~isfield(info, 'ResolutionUnit')
    return;
end
unit = info.ResolutionUnit;
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
end
end

function validateRgbImage(image)
if ~isa(image, 'uint8') || ~isreal(image) || ndims(image) ~= 3 || ...
        size(image, 3) ~= 3
    error('smokeGuiWorkflow:InvalidImage', ...
        '输入图像必须是 uint8 三通道 RGB 图像。');
end
end
