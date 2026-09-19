classdef ImageMetadataHelper
    %IMAGEMETADATAHELPER 图像元数据提取、分辨率物理转换与无损写盘辅助类。
    %   解耦主 App 中的底层图像格式与分辨率元数据校验逻辑。

    methods (Static)
        function format = normalizedFormat(extension)
            % 统一保存格式名称，非 PNG 输入按 JPG 处理。
            if strcmpi(extension, '.png')
                format = 'png';
            else
                format = 'jpg';
            end
        end

        function hasResolution = hasResolutionMetadata(imageInfo)
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

        function writeImageWithResolution(imageData, outputPath, imageInfo)
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

        function same = hasSameResolution(inputInfo, outputInfo)
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

            [inputResolution, inputValid] = gui_helpers.ImageMetadataHelper.resolutionInMeters(inputInfo);
            [outputResolution, outputValid] = gui_helpers.ImageMetadataHelper.resolutionInMeters(outputInfo);
            if ~inputValid || ~outputValid
                same = isequal(inputInfo.XResolution, outputInfo.XResolution) && ...
                    isequal(inputInfo.YResolution, outputInfo.YResolution);
                return;
            end

            same = all(abs(outputResolution - inputResolution) <= ...
                max(1, abs(inputResolution) * 1e-6));
        end

        function [resolution, valid] = resolutionInMeters(info)
            % 将常见分辨率单位换算为米制像素密度以便等值比对。
            resolution = [0, 0];
            valid = false;
            if ~isstruct(info) || ~isscalar(info) || ...
                    ~all(isfield(info, {'XResolution', 'YResolution'}))
                return;
            end
            if ~isnumeric(info.XResolution) || ~isnumeric(info.YResolution) || ...
                    ~isscalar(info.XResolution) || ~isscalar(info.YResolution) || ...
                    ~isfinite(info.XResolution) || ~isfinite(info.YResolution) || ...
                    info.XResolution <= 0 || info.YResolution <= 0
                return;
            end

            resolution = double([info.XResolution, info.YResolution]);
            valid = true;
            if ~isfield(info, 'ResolutionUnit')
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
                otherwise
                    % unknown 单位只能比较原始数值，不能进行物理换算。
            end
        end
    end
end
