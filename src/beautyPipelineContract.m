function contract = beautyPipelineContract
%BEAUTYPIPELINECONTRACT 返回当前生产 Context 契约与 v3.3 算法版本。
%   三个版本号职责必须分开维护，不得混用：
%     schemaVersion — Context 公共契约形态（当前 '4.0'，V4 layered）。
%       它只描述 Context 字段布局；升级它不代表算法行为或缓存产物
%       发生变化。T08（2026-09-19）起默认生产输出从 '3.1' compat 形态
%       切换为 '4.0' canonical 分层形态：这是一次有意冻结的纯架构
%       schema expand（新增 semantic/processability/evidence/protection/
%       diagnostics 分层），算法行为保持不变；'3.1' compat 形态
%       仍是缓存读者与 normalize/migrate 的合法旧形态。
%     algorithmVersion — 生产行为版本（'v3.3'）。只有算法效果或
%       管线行为变化时才递增；纯架构迁移保持不变。
%     artifactVersion — 缓存/产物兼容版本（'v3.2'）。运行时缓存的
%       有效性以它为准；Context schema 迁移不得改动该版本，否则会
%       造成无意义的全量缓存重建。

contract = struct( ...
    'schemaVersion', '4.0', ...
    'algorithmVersion', 'v3.3', ...
    'artifactVersion', 'v3.2');
end
