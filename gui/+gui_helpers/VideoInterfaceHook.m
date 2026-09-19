classdef VideoInterfaceHook < handle
    %VIDEOINTERFACEHOOK 视频人像美颜预留接口与播放状态机管理类。
    %   负责管理视频流加载、时间轴跳转、时域平滑防闪烁开关与批量导出预留钩子。

    properties (Access = public)
        VideoPath = ''
        IsVideoLoaded = false
        TotalFrames = 0
        CurrentFrame = 1
        FrameRate = 30.0
        IsPlaying = false
        IsDeflickerEnabled = true
        PlaybackTimer = []
        VideoReaderObj = []
    end

    methods
        function obj = VideoInterfaceHook()
            % 构造函数
        end

        function delete(obj)
            % 析构时清理定时器
            if ~isempty(obj.PlaybackTimer) && isvalid(obj.PlaybackTimer)
                stop(obj.PlaybackTimer);
                delete(obj.PlaybackTimer);
            end
        end

        function success = openVideoFile(obj, app, filePath)
            % 加载视频源并提取元数据
            success = false;
            try
                if isempty(filePath) || ~isfile(filePath)
                    uialert(app.UIFigure, '视频文件不存在或路径无效。', '打开视频失败');
                    return;
                end
                vr = VideoReader(filePath);
                obj.VideoReaderObj = vr;
                obj.VideoPath = filePath;
                obj.FrameRate = vr.FrameRate;
                if isprop(vr, 'NumFrames') && vr.NumFrames > 0
                    obj.TotalFrames = vr.NumFrames;
                else
                    obj.TotalFrames = max(1, round(vr.Duration * vr.FrameRate));
                end
                obj.CurrentFrame = 1;
                obj.IsVideoLoaded = true;
                success = true;
            catch ex
                uialert(app.UIFigure, ['无法读取视频文件: ' ex.message], '视频加载异常');
            end
        end

        function timecode = formatTimecode(obj, frameIdx, fps)
            % 格式化为 SMPTE 时间码 (HH:MM:SS:FF)
            if nargin < 3 || isempty(fps)
                fps = obj.FrameRate;
            end
            if fps <= 0, fps = 30.0; end
            totalSec = floor(frameIdx / fps);
            ff = floor(mod(frameIdx, fps));
            ss = floor(mod(totalSec, 60));
            mm = floor(mod(floor(totalSec / 60), 60));
            hh = floor(totalSec / 3600);
            timecode = sprintf('%02d:%02d:%02d:%02d', hh, mm, ss, ff);
        end

        function stepFrame(obj, app, delta)
            % 逐帧步进
            if ~obj.IsVideoLoaded, return; end
            if obj.IsPlaying
                obj.togglePlay(app);
            end
            target = max(1, min(obj.TotalFrames, obj.CurrentFrame + delta));
            obj.seekFrame(app, target);
        end

        function seekFrame(obj, app, targetFrame)
            % 跳转指定帧
            if ~obj.IsVideoLoaded, return; end
            obj.CurrentFrame = max(1, min(obj.TotalFrames, targetFrame));
            app.onVideoFrameChanged(obj.CurrentFrame);
        end

        function togglePlay(obj, app)
            % 播放 / 暂停切换
            if ~obj.IsVideoLoaded, return; end
            obj.IsPlaying = ~obj.IsPlaying;
            if obj.IsPlaying
                if isempty(obj.PlaybackTimer) || ~isvalid(obj.PlaybackTimer)
                    obj.PlaybackTimer = timer('ExecutionMode', 'fixedRate', ...
                        'Period', max(0.033, round(1/obj.FrameRate, 3)), ...
                        'TimerFcn', @(~,~) obj.timerTick(app));
                end
                start(obj.PlaybackTimer);
                app.VideoPlayButton.Text = '暂停预览';
            else
                if ~isempty(obj.PlaybackTimer) && isvalid(obj.PlaybackTimer)
                    stop(obj.PlaybackTimer);
                end
                app.VideoPlayButton.Text = '播放预览';
            end
        end

        function timerTick(obj, app)
            % 定时器帧回调
            if ~obj.IsVideoLoaded || ~obj.IsPlaying, return; end
            if obj.CurrentFrame < obj.TotalFrames
                obj.CurrentFrame = obj.CurrentFrame + 1;
            else
                obj.CurrentFrame = 1;
            end
            app.onVideoFrameChanged(obj.CurrentFrame);
        end

        function exportVideo(obj, app, outputPath)
            % 视频批量导出预留钩子
            if ~obj.IsVideoLoaded
                uialert(app.UIFigure, '请先打开视频文件再执行导出。', '无有效视频源');
                return;
            end
            uialert(app.UIFigure, ...
                sprintf('视频导出管道就绪：\n- 目标路径: %s\n- 帧率: %.2f FPS\n- 视频美颜流水线 (规划阶段接口)', ...
                outputPath, obj.FrameRate), '视频导出流水线');
        end
    end
end
