classdef GuiTheme
    %GUITHEME 统一的深色工作室调色台风格与样式配置系统。
    %   为 MATLAB App Designer 组件提供统一的色彩、字体与边框样式，
    %   消除界面单调感并确保单图与视频模式的视觉风格一致。

    properties (Constant)
        % 基础背景色
        BgRoot          = [0.03, 0.05, 0.09];    % 窗口主背景 (#070b13)
        BgCard          = [0.05, 0.08, 0.15];    % 卡片面板背景 (#0d1527)
        BgCardSub       = [0.04, 0.06, 0.11];    % 次级容器背景 (#0a101c)
        BgAxes          = [0.02, 0.03, 0.06];    % 图像视窗底色 (#05080f)

        % 边框与分割线
        BorderMuted     = [0.12, 0.16, 0.24];    % 幽暗边框 (#1e293b)
        BorderHighlight = [0.18, 0.25, 0.36];    % 聚焦外框 (#2e405c)

        % 文本颜色
        TextPrimary     = [0.92, 0.95, 0.98];    % 主标题/正文浅白
        TextMuted       = [0.55, 0.63, 0.75];    % 次要描述文字
        TextHighlight   = [0.22, 0.74, 0.97];    % 极光青强调色 (#38bdf8)
        TextAmber       = [0.98, 0.75, 0.22];    % 琥珀提示色 (#f59e0b)
        TextEmerald     = [0.20, 0.83, 0.60];    % 成功指示绿 (#34d399)

        % 按钮色彩
        BtnPrimaryBg    = [0.08, 0.50, 0.78];    % 主操作按钮背景 (天蓝)
        BtnPrimaryText  = [1.00, 1.00, 1.00];
        BtnSecondaryBg  = [0.12, 0.17, 0.26];    % 次操作按钮背景 (板岩蓝)
        BtnSecondaryText= [0.85, 0.90, 0.95];
        BtnActiveBg     = [0.02, 0.40, 0.65];    % 激活按钮底色
    end

    methods (Static)
        function applyFigureStyle(fig, name)
            % 配置主窗口全局背景与尺寸
            fig.Color = gui_helpers.GuiTheme.BgRoot;
            fig.Name = name;
        end

        function applyPanelStyle(panel, titleText)
            % 配置标准毛玻璃卡片风格面板
            panel.BackgroundColor = gui_helpers.GuiTheme.BgCard;
            panel.ForegroundColor = gui_helpers.GuiTheme.TextPrimary;
            panel.BorderType = 'line';
            panel.BorderWidth = 1;
            panel.HighlightColor = gui_helpers.GuiTheme.BorderHighlight;
            if nargin >= 2 && ~isempty(titleText)
                panel.Title = titleText;
                panel.FontWeight = 'bold';
                panel.FontSize = 11;
            end
        end

        function applySubPanelStyle(panel)
            % 配置嵌套次级面板
            panel.BackgroundColor = gui_helpers.GuiTheme.BgCardSub;
            panel.ForegroundColor = gui_helpers.GuiTheme.TextMuted;
            panel.BorderType = 'line';
            panel.BorderWidth = 1;
            panel.HighlightColor = gui_helpers.GuiTheme.BorderMuted;
        end

        function applyButtonStyle(btn, variant)
            % 统一按钮视觉变体 ('primary', 'secondary', 'action', 'mode')
            if nargin < 2
                variant = 'secondary';
            end
            btn.FontSize = 11;
            btn.FontWeight = 'bold';
            switch lower(variant)
                case 'primary'
                    btn.BackgroundColor = gui_helpers.GuiTheme.BtnPrimaryBg;
                    btn.FontColor = gui_helpers.GuiTheme.BtnPrimaryText;
                case 'secondary'
                    btn.BackgroundColor = gui_helpers.GuiTheme.BtnSecondaryBg;
                    btn.FontColor = gui_helpers.GuiTheme.BtnSecondaryText;
                case 'active_mode'
                    btn.BackgroundColor = gui_helpers.GuiTheme.BtnActiveBg;
                    btn.FontColor = [1.0, 1.0, 1.0];
                otherwise
                    btn.BackgroundColor = gui_helpers.GuiTheme.BtnSecondaryBg;
                    btn.FontColor = gui_helpers.GuiTheme.BtnSecondaryText;
            end
        end

        function applyAxesStyle(ax, titleText)
            % 配置专业图像暗色视窗
            ax.Color = gui_helpers.GuiTheme.BgAxes;
            ax.XColor = 'none';
            ax.YColor = 'none';
            ax.Box = 'off';
            ax.Toolbar.Visible = 'off';
            if nargin >= 2 && ~isempty(titleText)
                title(ax, titleText, 'Color', gui_helpers.GuiTheme.TextPrimary, ...
                    'FontSize', 11, 'FontWeight', 'bold', 'Interpreter', 'none');
            end
        end

        function applyLabelStyle(lbl, role)
            % 配置文本标签 ('primary', 'muted', 'highlight', 'amber')
            if nargin < 2
                role = 'primary';
            end
            switch lower(role)
                case 'muted'
                    lbl.FontColor = gui_helpers.GuiTheme.TextMuted;
                    lbl.FontSize = 10;
                case 'highlight'
                    lbl.FontColor = gui_helpers.GuiTheme.TextHighlight;
                    lbl.FontWeight = 'bold';
                    lbl.FontSize = 11;
                case 'amber'
                    lbl.FontColor = gui_helpers.GuiTheme.TextAmber;
                    lbl.FontWeight = 'bold';
                    lbl.FontSize = 11;
                otherwise
                    lbl.FontColor = gui_helpers.GuiTheme.TextPrimary;
                    lbl.FontSize = 11;
            end
        end

        function applySliderStyle(slider)
            % 配置数值滑块
            slider.FontColor = gui_helpers.GuiTheme.TextMuted;
            slider.FontSize = 9;
        end

        function applyGridLayout(grid, bgColor)
            % 强制赋予网格深色背景，消除 MATLAB 默认 [0.94, 0.94, 0.94] 浅灰遮罩
            if nargin < 2 || isempty(bgColor)
                bgColor = gui_helpers.GuiTheme.BgCard;
            end
            grid.BackgroundColor = bgColor;
        end
    end
end
