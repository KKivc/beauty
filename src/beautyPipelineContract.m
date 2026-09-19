function contract = beautyPipelineContract
%BEAUTYPIPELINECONTRACT 返回 v3.1 数据结构和 v3.2 算法使用的固定契约版本。
%   三个版本号职责必须分开维护，不得混用：
%     schemaVersion — Context 公共契约形态（当前 '3.1' compat；V4
%       layered 为 '4.0'）。它只描述 Context 字段布局；升级它不代表
%       算法行为或缓存产物发生变化。
%     algorithmVersion — 生产行为版本（'v3.2'）。只有算法效果或
%       管线行为变化时才递增；纯架构迁移保持不变。
%     artifactVersion — 缓存/产物兼容版本（'v3.1'）。运行时缓存的
%       有效性以它为准；Context schema 迁移不得改动该版本，否则会
%       造成无意义的全量缓存重建。

contract = struct( ...
    'schemaVersion', '3.1', ...
    'algorithmVersion', 'v3.2', ...
    'artifactVersion', 'v3.1');
end
