function protection = buildStageProtectionMasks(beautyMasks, policyEvidence)
%BUILDSTAGEPROTECTIONMASKS 从 v3.1 Beauty Masks 推导 V4 stage protection。
%   T07 兼容阶段：把当前 texture/structure/chroma/whitening/hard/nose
%   门控按各生产 stage 的真实组合方式映射为 stage 字段，只做行为
%   等价的 algebra 组合，不重新设计任何权重。
%
%   T31（执行契约）：发布规范双门控 target.*/support.*（上位契约第 2 节
%   "目标保护 / 支撑保护双门控"）。target.* = 该像素能不能被修改，
%   support.* = 该像素能不能作为邻域计算的参考样本；T07 的扁平折叠名
%   smoothingFine/smoothingMid/repairFine/repairMid 迁入 target.* 并删除
%   旧名（同一语义只留一个规范字段）。support.* 把 legacy consumer 原先
%   自行组合/读取的参考池门与结构锚点上移到本层一次算好，零带取值与
%   T30 之前 consumer 侧同名基准逐位一致。执行层算法自此只允许读
%   target.*/support.*/hard（及 strength 层与运行期证据），不再读取
%   semantic/evidence/*ProtectionMask/noseMask 去重新判定保护。
%
%   T30（region policy gate activation）：在本层额外发布五条纯 policy
%   带 regionBandFine/regionBandMid/regionBandBase/regionBandTone/
%   regionBandWhitening（见文末"T30 纯 policy 带"段），把 T20/T21/T22
%   的分级保护从"仅作用于折叠快照"改为真正注入消费侧算术门控；带与
%   legacy 折叠式解耦，缺省/零带时逐位还原 legacy。
%
%   T20（eye/lip identity policy）：本函数新增可选第二输入
%   policyEvidence（masks.buildBeautyPolicyEvidence 的第一输出，经
%   rebuildBeautyDerivedMasks 桥接传入；生产调用点 beautifyImage 从
%   normalized Context 的 evidence 层转发）。提供且包含 periocular/lip
%   字段时，对眼周/唇周执行三带分级保护 policy（T20）；提供且包含
%   nostril/noseStructure 字段时，对鼻部执行 identity/structure/skin
%   分级保护 policy（T21，见下）：
%
%     identity core —— 眼语义（>= .65，经 occluderHard）、检测睫毛
%       lashCore、唇核 lipCore。它们已全部位于 hardProtectionMask，
%       T20 不新增任何 hard 像素（hard 原样拷贝，严格二值不变）。
%     soft detail band —— 紧贴 identity core 的检测细节带：
%       eyeDetailBand  = smoothStep(periocular, .50, .78)
%       lipDetailBand  = smoothStep(lip, .55, .85)
%       依据：periocular 的几何环峰值为 .76（featherSoftMask 峰值），
%       检测睫毛/双眼皮褶皱核心为 .99/.92，故 .78 上支撑点≈"检测细节
%       核心 + 环带内缘"，.50 下支撑点≈环带内 1/3（d ≈ .34·R）；
%       lip 环峰值为 .90（lipRadius 羽化），.85/.55 对应环带内缘与
%       内 39%（d ≈ .39·r）。两带的上下支撑点均为各自峰值的固定比例
%       （≈1.03 峰值与 ≈0.66/0.61 峰值），随脸尺度自适应。
%     skin transition band —— 环带外半程的皮肤过渡带：
%       eyeTransition = smoothStep(periocular, .08, .40)
%       lipTransition = smoothStep(lip, .12, .50)
%       依据：上支撑点≈各峰值的 53%/56%（环带中点，d ≈ .47·R），
%       下支撑点≈峰值的 11%/13%（羽化尾部消失处，d ≈ .9·R）。
%       detail 与 transition 用 (1 - detailBand) 互斥，避免双重计入。
%
%     七个 stage 字段的差异化分配（全部以 max/min 作用于 T07 legacy
%     折叠式， Bands 全零时与 legacy 逐位相等）：
%       texture 通道替换 —— 环带内把 texture 中 eye/lip 的贡献替换为
%         policy 值（texture 是合并 max，无法逐分量剥离，只能在
%         evidence 圈定的带内整体替换；structure 门保持乘子原位，
%         结构保护不受 cap 影响）：
%         policyTexture = max(texture, .95·detailBand)
%         policyTexture = min(policyTexture, 1 - .55·transitionBand)
%         .95 取检测细节保护区间 .92（fold）--.99（lash）的中点，细节
%         带内 Fine 门只剩 <=5%；cap 在满权重处保留 >=55% 的 Fine 处
%         理量——legacy 环带 plateau 为 .76--.90（唇环甚至低于 .80 可
%         处理线，形成未处理环带），.55 是普通皮肤（100%）与细节带
%         （5%）的中点。作用于 smoothingFine/repairFine/baseLuminance。
%       Mid 家族（smoothingMid/repairMid）补保护：legacy 折叠不含
%         texture，睫毛/双眼皮褶皱/唇缘的中频细节此前被全强度磨除。
%         smoothingMid 等字段取 max(legacy, .90·detailBand,
%         .30·transitionBand)：.90 与检测细节区间对齐；.30 过渡带轻
%         保护维持眼窝/唇周中频明暗连续，同时保留 >=70% 中频处理量。
%       tone：max(legacy, .90·lipDetailBand)——唇色是 identity 色度，
%         只对唇细节带生效；眼周色度无额外 identity 语义，仍由
%         chroma 保护承载。
%       whitening：max(legacy, .85·detailBand)——防止唇缘/眼缘假白
%         光晕；略低于 Fine 侧 .95，避免美白场在带边形成自身台阶。
%         过渡带不设 cap：眼周/唇周皮肤亮度应与全脸连续。
%
%   消费侧（T30 已激活）：smoothingFine/smoothingMid/hard 被
%   smoothSkinTexture（T12/T13）直接用于输出算术；repairFine/
%   repairMid/baseLuminance/tone/whitening 的分级数值经纯 policy 带
%   regionBand* 注入对应 consumer 的算术门控（见文末"T30 纯 policy
%   带"段），T20 的 eye/lip 分级保护因此全部生效。
%
%   T21（nose region policy）：在 eye/lip 三带之外新增鼻部分级保护。
%   policyEvidence 新增消费 nostril/noseStructure 两个语义字段（T06
%   evidence 层既有字段，不自造检测模型）：
%     nostril identity core —— evidence.nostril（0/1，鼻孔暗谷核心，
%       由暗谷+梯度+面积/连续度几何筛选产生的高置信 dark/geometry
%       证据）。它已全部位于 hardProtectionMask，T21 不新增任何 hard
%       像素（hard 原样拷贝，严格二值不变）。
%     nostril detail band（鼻孔边缘软带）——
%       nostrilDetailBand = smoothStep(nostrilEdge, .40, .80)，
%       nostrilEdge = max(0, 1 - bwdist(nostrilCore)/(r+1))，
%       r = min(4, max(2, round(.006*faceScale)))，faceScale 取自
%       beautyMasks.faceScale（缺失且 nostril 证据非零时 fail-fast）。
%       依据：nostrilEdge 与 v3.1 texture 通道已有的鼻孔软羽化
%      （buildTextureProtectionMask 的 nostrilProtection，峰值 .95、
%       同一 r 公式）同 footprint；上支撑点 .80 ≈ 羽化内圈 1px
%      （d≈.2r，暗边界内缘），下支撑点 .40 ≈ 羽化中点半径
%      （d≈.6r）。band 只覆盖既有软羽化的 ≥.40 内圈，是 2--5px 的
%       软带而非大半径硬膨胀（带外几何零扩张）。nostrilCore 本身
%       hard 已满分，band 的作用是把 core 外 1--2px 暗边界的 Fine/
%       Mid 保护从羽化衰减改为固定档位平台。
%     nose structure band（鼻梁/鼻翼结构带）——
%       noseStructureBand = smoothStep(noseStructure, .15, .50)。
%       依据：evidence.noseStructure = 鼻语义支持 × 低频梯度 × 方向
%       一致性（P55/P95 分位归一）。真实图实测（77 链路）鼻内
%       P90=.071、P95=.368、max=.75，故 .15 下支撑点只让最强的
%       5--10% 结构证据进入带（普通鼻皮肤零带、保持 processability）；
%       上支撑点 .50 ≈ 2× v3.1 结构门饱和点（structure≥.25 时
%       fineStructureGate=0）。带内主要抬升 Mid 家族与 baseLuminance：
%       smoothingMid/repairMid 补 .85·band、baseLuminance 补
%       .80·band；Fine（texture 通道）与 tone/whitening 不进结构带
%       ——鼻梁/鼻翼是光影结构而非 identity 细节，美白/调色必须与
%       脸颊连续（工单第 2/3 步）。
%     鼻部分配（全部以 max 作用于 T07/T20 折叠式，带为零时逐位相等）：
%       policyTexture 追加 max(.95·nostrilDetailBand)（.95 与 v3.1
%         nostrilProtection 峰值对齐；结构带不进 texture 通道）；
%       smoothingMid/repairMid 追加 max(.90·nostrilDetailBand,
%         .85·noseStructureBand)（.90 与 T20 检测细节档位一致，
%         .85 给光影结构保留 ≥15% 中频处理量）；
%       baseLuminance 追加 max(.80·noseStructureBand)（鼻梁低频
%         明暗是立体感主载体；.80 保留 ≥20% 亮度均衡量维持与脸颊
%         的亮度连续）；
%       whitening 追加 max(.85·nostrilDetailBand)（仅鼻孔软带内防
%         假白光晕，与 T20 eye/lip 细节带同档；鼻皮肤不设任何美白
%         退让）；
%       tone 不追加任何鼻部项：鼻部无 identity 色度语义，肤色变化
%         与脸颊连续（本快照与 T17 consumer 均不变）。
%       两带可能重叠（鼻孔边缘梯度强），stage 字段全部取 max，重叠
%       不双重计入。
%
%   消费侧（T30 已激活，与 T20 相同）：smoothingFine/smoothingMid/
%   hard 被 smoothSkinTexture（T12/T13）直接用于输出算术；nostril 带
%   的 Fine/Mid 保护同时经 regionBandFine/regionBandMid 注入 repair 的
%   textureGate/noseMidGate，鼻结构带经 regionBandMid/regionBandBase
%   注入 repair.noseMidGate/evenSkinLuminance.regionBandGate。T21 不改变
%   T07 legacy 折叠里的整鼻 .50 Mid 门（零带/compat 时必须逐位还原
%   legacy）；鼻皮肤的可处理性由证据带门槛（.15/.40 下支撑点）保证，
%   普通鼻皮肤零带、不新增任何冻结。
%
%   T22（ear region policy）：在 eye/lip/nose 之外新增耳部结构带。
%   policyEvidence 新增消费 T22 evidence 字段 earStructure（耳语义
%   支持域 × max(continuousEvidence, darkDetail)，见
%   masks.buildBeautyPolicyEvidence 的 T22 段）：
%     ear structure band（耳轮/耳甲腔结构带）——
%       earStructureBand = smoothStep(earStructure, .05, .30)。
%       依据（真实图 77 实测，ear semantic >= .20 域内 5744px）：
%       earStructure P10=0.000、P25=.004、P50=.144、P75=.570、P90=.931，
%       故 .05 下支撑点≈P31（真实平坦耳皮肤零带、保持 processability），
%       .30 上支撑点≈P60（耳轮脊线/耳甲腔壁/对耳轮褶皱的"高于中位数
%       结构"进入满档）；band>.5 footprint 约 2.7e3 px，全部位于 ear
%       semantic 支持域内（ear<.20 处 band 严格为 0，实测耳外非零像素
%       数 0）——工单第 4 条：不用纯几何扩张，耳外背景不被误纳入。
%     耳部分配（全部以 max 作用于 T07/T20/T21 折叠式，带为零时逐位
%     相等）：
%       texture 通道（policyTexture）追加 max(.95·earStructureBand)：
%         真实图实测耳内 legacy alphaMap 均值 .322（Fine 门未饱和），
%         结构带进入 texture 通道后在 band 内改变 1743px 的
%         smoothingFine；实测（smoothing-only 重建，耳域高频 std）
%         耳结构带只进 Mid 时高频保留 +1.7%，Mid+Fine 同时进入时
%         +3.8%，故 Fine 侧必须参与才能有效保留耳轮/沟槽细节。.95 与
%         T20 检测细节带/T21 鼻孔软带同档，保留 >=5% 的 Fine 处理量
%         维持耳皮肤自然质感。
%       smoothingMid/repairMid 追加 max(.90·earStructureBand)：耳轮
%         脊线与耳甲腔沟槽的尺度（真实图 mediumSigma=12.9px，脊线宽
%         约 8--15px）主要落在 Mid 频段，故 Mid 家族是结构保护主载体；
%         .90 与 T20/T21 同档，保留 >=10% 中频处理量。
%       baseLuminance 追加 max(.80·earStructureBand)：耳轮亮脊与耳甲
%         腔暗谷的低频明暗对比是耳部立体感主载体（evenSkinLuminance
%         会均衡低频亮度）；.80 与 T21 鼻结构带同档，保留 >=20% 亮度
%         均衡量。
%       tone/whitening 不追加任何耳部项（工单第 2 步：保持更低保护、
%         维持耳部与脸部/颈部肤色连续）：耳部无 identity 色度语义；
%         真实图实测 legacy 耳-颊保护差为 tone +.0475、whitening
%         +.0191（耳部本就更高保护），任何耳带项都会放大该差，形成
%         耳-颊异色块/割裂。本 policy 因此让耳-颊 tone/whitening 差与
%         legacy 逐位相同（不新增割裂）。
%       hard 不追加任何耳部项：耳轮/沟槽一律软保护，不整耳 hard 化
%         （工单第 3 步），hard 原样拷贝、nnz 不变。
%     两带（ear 结构带与 eye/lip/nose 带）可能重叠，stage 字段全部取
%     max，重叠不双重计入。
%
%   消费侧现状（T30 已激活，T31 收口）：beautifyImage 的 stage contract
%   组装把本层发布的纯 policy 带 regionBand* 注入各 stage 的真实算术门控
%   （gate := gate .* (1 - band)，见 beautifyImage 的
%   makeBaseLuminanceStageContract/makeToneStageContract/
%   makeWhiteningStageContract 与 +beauty/repairStageContract）：
%     regionBandFine     → repair.textureBandGate（只乘 Fine/Mid/chroma
%                          逐像素权重，不进 referenceReliability）；
%     regionBandMid      → repair 的鼻部/过渡 Mid 追加保护（仅
%                          mediumWeight，不与纹理门重复计入）；
%     regionBandBase     → evenSkinLuminance 的 regionBandGate（只作用于
%                          逐像素 supportMap，不进全局参考统计）；
%     regionBandTone     → normalizeSkinTone.featureGate（主分支）；
%     regionBandWhitening→ applySkinWhitening.featureGate。
%   T31 起 consumer 侧只允许读 target.*/support.*/hard（及 strength 层
%   与运行期证据），不得再自行解释 general masks。smoothSkinTexture
%   （T12/T13/T31）读 target.smoothingFine/smoothingMid +
%   support.smoothingFine/smoothingMid + hard；repairSkinBlemishes
%   （T14/T15/T31）读 producer 组装层按本层 support.* 重建的
%   target/support 门；compose hard restore（T19）读 hard。
%   因此 T20/T21/T22 的分级保护不再只作用于快照，而是真正进入输出算术。
%   带外（band == 0）时 gate .* 1 与 legacy 逐位相等，compat 路径与零带
%   路径输出逐位不变；耳部瑕疵修复（blemishMap 驱动）仍不在本层可控
%   范围内。
%
%   统一语义：protection 字段是"该 stage 施加的保护量"，取值 [0,1]，
%   消费侧用 gate = 1 - protection（或 1 - max(field, hard)）还原生产
%   门控。三个边界约定（与 T12--T19 的 consumer contract 一致）：
%     * hard identity 不并入任何 stage 字段：protection.hard 单独发布，
%       各 stage 按生产原位（max 合并或 (1-hard) 乘子）自行组合；
%     * strengthMap/effectStrengthMap 保持独立：profile.alphaCurve、
%       strengthMap 等强度侧标量一律不进入本层；
%     * runtime 证据（blemishMap 及其耦合的 structure gate 放宽）不进
%       入本层，字段记录其在零瑕疵参考点的快照（见 repairFine 说明）。
%
%   字段语义分三类（T31 定稿，T32/T33 沿用）：
%     * protection.target.<stage> —— 目标保护门（上位契约第 2 节）：
%       该像素"能不能被修改"，0 = 可自由修改，1 = 完全不可修改。T31
%       发布 smoothingFine/smoothingMid/repairFine/repairMid 四个规范
%       字段；T07 的扁平折叠名（smoothingFine/smoothingMid/repairFine/
%       repairMid）在同一语义上被 target.* 取代并删除，不允许并存两个
%       真值来源。baseLuminance/tone/whitening 仍为扁平字段，留待
%       T32/T33 迁移。
%     * protection.support.<stage> —— 支撑保护门：该像素"能不能作为
%       邻域计算的参考样本"，0 = 完全可作为参考，1 = 不可作为参考。
%       零带取值逐位等于 T30 之前各 stage 参考池/统计池的等价基准门：
%         support.smoothingFine = max(texture, structure, hard)
%           —— legacy `beautyMasks.protectionMask` 的等价合并（smoothing
%              统计池门，T07/T12 起由 consumer 直接读取该合并产物）；
%         support.smoothingMid  = min(4·structure, 1)
%           —— legacy Mid 结构锚点门 fineStructureGate = max(0,1-4·structure)
%              的补码（1 - support.smoothingMid 逐位还原该锚点）；
%         support.repairFine    = texture
%           —— repair 邻域参考池的纹理保护源（1 - support.repairFine 逐位
%              等于生产 textureGate = 1 - texture）；
%         support.repairMid     = structure
%           —— repair 邻域参考池的结构保护源（供 producer 按生产原式
%              重建 blemish 放宽结构门与强结构上限）。
%     * protection.noseMidProtection —— T31 过渡扁平字段：repair Mid 的
%       鼻部退让保护 .50·nose（= 1 - noseMidGate）。鼻部语义尚未纳入
%       target/support 规范名（与 regionBand* 同为过渡扁平字段），
%       consumer 用 noseMidGate = 1 - noseMidProtection 还原生产门控。
%     * 五条 regionBand* 纯 policy 带 —— 追加保护量，消费侧用
%       gate := gate .* (1 - band) 注入；它们才是分级保护的激活载体。
%
%   legacy 折叠式（T07 推导，Bands 全零时逐位还原；T31 起发布为
%   target.* 规范名）：
%     target.smoothingFine
%       beauty.smoothSkinTexture 的 Fine 门控（fineProtection =
%       max(texture, hard) 与 fineStructureGate = max(0, 1-4*structure)，
%       alphaMap = effectStrength .* (1 - fineProtection) .*
%       fineStructureGate）：hard 走 max 合并，余下部分折叠为
%       target.smoothingFine = 1 - (1 - texture) .* max(0, 1 - 4*structure)。
%       重算 alphaMap = effectStrength .* (1 - max(target.smoothingFine, hard))
%       与生产逐像素等价。
%     target.smoothingMid
%       同函数 Mid 分支的额外门控（midStructureGate = fineStructureGate
%       与 noseMidGate = 1 - .50*nose.*profile.alphaCurve）：nose 项取
%       生产系数 .50 的满档快照（alphaCurve=1；alphaCurve 的强度插值
%       属 effect-strength 侧，见上），折叠为
%       target.smoothingMid = 1 - fineStructureGate .* (1 - .50*nose)。
%       重算 midAlphaMap = alphaMap .* (1 - target.smoothingMid) 在
%       alphaCurve=1 时与生产等价；alphaCurve<1 时生产 nose 门控为
%       1 与该快照的凸组合（快照即最强保护），强度无关结构锚点由
%       support.smoothingMid 提供。
%     target.repairFine
%       beauty.repairSkinBlemishes 的 fineWeight 门控（structureGate =
%       min(1 - structure.*(1-.90*blemish), 1 - .65*strongStructure)，
%       strongStructure = smoothStep(structure,.70,.90) .* (hard 特征
%       3px 带)；textureGate = 1 - texture 线性作用；allowed 中的
%       (1-hard) 单独保留）：记录零瑕疵参考点 structureGate0 =
%       min(1 - structure, 1 - .65*strongStructure)，折叠为
%       target.repairFine = 1 - structureGate0 .* (1 - texture)。runtime
%       blemish 证据只放宽 structureGate（≥ structureGate0），由
%       producer 按 support.repairMid 重建后随 contract 消费。
%     target.repairMid
%       同函数 mediumWeight 门控：与 fine 共享 structureGate，另有
%       noseMidGate = 1 - .50*nose（repair 侧无 alphaCurve，完全静态）
%       与 textureGate：target.repairMid = 1 - structureGate0 .*
%       (1 - .50*nose) .* (1 - texture)。零瑕疵参考点重算与生产等价。
%     support.smoothingFine / support.smoothingMid / support.repairFine /
%     support.repairMid
%       T31 新增的支撑保护门（见文首"字段语义分三类"）：分别为
%       max(texture, structure, hard)、min(4·structure, 1)、texture、
%       structure。它们不是新的行为折叠，而是把 legacy consumer 原先
%       自行组合/读取的参考池门与结构锚点上移到 policy 层一次算好，
%       零带取值与 T30 之前 consumer 侧的同名基准逐位一致。
%     baseLuminance
%       beauty.evenSkinLuminance 的 supportMap 门控（structureGate =
%       1 - structure；featureProtection = max(texture, chroma)；
%       hardProtectionGate = 1 - hard 单独保留）：
%       baseLuminance = 1 - (1 - structure) .* (1 - max(texture, chroma))。
%       supportMap = baseWeightCurve .* regionalSkinWeight .* (1-hard) .*
%       (1 - baseLuminance) .* referenceCoverage 与生产逐像素等价。
%     tone
%       beauty.normalizeSkinTone 主 weight 分支（structureGate =
%       1 - structure；featureGate = 1 - .78*chroma；allowed 中的
%       (1-hard) 单独保留）：tone = 1 - (1 - structure) .*
%       (1 - .78*chroma)。已知残差：ratio>.50 的 uniform 分支使用
%       (1-structure).*(1-chroma)（比本字段更强），单快照无法同时
%       表达两条分支；T17 起消费侧改由生产端拼装的未折叠
%       uniformFeatureGate 字段精确重建该分支，本快照只作主分支参考
%       （toneGateSnapshot）。
%     whitening
%       beauty.applySkinWhitening 的 supportBase 门控（featureSetback =
%       1 - whitening；structureGate = 1 - structure，脸部（faceSkin
%       >= .5）浅退让为 1 - .10*structure；allowed 中的 (1-hard) 单独
%       保留）：whitening = 1 - structureGateWhitening .* (1 - whitening)。
%       supportBase 重算与生产逐像素等价。
%     hard
%       buildTextureProtectionMask 的 hardProtectionMask =
%       double(occluderHard | lipCore | nostrilCore | lashCore)，原样
%       拷贝（bit-exact，二值 identity）。T20 不扩大 hard：eye/lip
%       identity core 已在其中，soft band / transition band 一律不进
%       hard。
%
%   输入参数：
%     beautyMasks — masks.buildBeautyMasks 的第一输出（含
%                   texture/structure/chroma/whitening/hardProtection、
%                   noseMask、faceSkinMask）；v3.1 顶层 Context 不直接
%                   作为输入，保证与生产门控共用同一份 mask 产物。
%     policyEvidence — 可选。masks.buildBeautyPolicyEvidence 的第一
%                   输出；T20 消费 periocular/lip，T21 追加消费
%                   nostril/noseStructure 两个鼻部语义字段，T22 追加
%                   消费 earStructure 耳部结构字段，其余字段仍与本层
%                   解耦。缺省（nargin<2）、空结构或缺少任一消费字段
%                   （partial V4）时按零带处理，输出与 T07 legacy 折叠
%                   逐位相等（含五条 regionBand* 全零）；字段存在但
%                   尺寸/取值非法时 fail-fast。

if nargin < 2
    policyEvidence = [];
end

requiredFields = {'textureProtectionMask', 'structureProtectionMask', ...
    'chromaProtectionMask', 'whiteningProtectionMask', ...
    'hardProtectionMask', 'noseMask', 'faceSkinMask'};
if ~isstruct(beautyMasks) || ~isscalar(beautyMasks) || ...
        ~all(isfield(beautyMasks, requiredFields))
    error('masks:InvalidMasks', ...
        'stage protection 需要完整的 v3.1 Beauty Masks 产物。');
end

texture = readMask(beautyMasks, 'textureProtectionMask');
structure = readMask(beautyMasks, 'structureProtectionMask');
chroma = readMask(beautyMasks, 'chromaProtectionMask');
whitening = readMask(beautyMasks, 'whiteningProtectionMask');
hard = readMask(beautyMasks, 'hardProtectionMask');
nose = readMask(beautyMasks, 'noseMask');
faceSkin = readMask(beautyMasks, 'faceSkinMask');
maskNames = {'textureProtectionMask', 'structureProtectionMask', ...
    'chromaProtectionMask', 'whiteningProtectionMask', ...
    'hardProtectionMask', 'noseMask', 'faceSkinMask'};
maskValues = {texture, structure, chroma, whitening, hard, nose, faceSkin};
for index = 2:numel(maskValues)
    if ~isequal(size(maskValues{index}), size(texture))
        error('masks:InvalidMasks', ...
            'Beauty Masks 字段 %s 与 textureProtectionMask 尺寸不一致。', ...
            maskNames{index});
    end
end

% T20：eye/lip 语义证据带。缺省或 partial evidence 时全部为零带，
% 后续所有 max/min 作用退化为恒等，输出与 T07 legacy 逐位相等。
[eyeField, lipField] = readEyeLipEvidence(policyEvidence, size(texture));
eyeDetailBand = smoothStep(eyeField, .50, .78);
eyeTransitionBand = smoothStep(eyeField, .08, .40);
lipDetailBand = smoothStep(lipField, .55, .85);
lipTransitionBand = smoothStep(lipField, .12, .50);
detailBand = max(eyeDetailBand, lipDetailBand);
transitionBand = max(eyeTransitionBand, lipTransitionBand) .* ...
    (1 - detailBand);

% T21：鼻部证据带（nostril 边缘软带 + 结构带）。缺省或 partial
% evidence 时同样为零带；两带重叠处 stage 字段取 max，不双重计入。
[nostrilDetailBand, noseStructureBand] = readNoseBands( ...
    policyEvidence, beautyMasks, size(texture));

% T22：耳部结构带（耳轮/耳甲腔沟槽）。缺省或 partial evidence 时为零带；
% 带由 ear 语义支持域约束，ear 语义支持域外严格为 0。
earStructureBand = readEarBands(policyEvidence, size(texture));
% T20/T21/T22 texture 通道替换：细节带内抬升到检测细节保护水平，过渡带
% 内封顶保留处理量；带外逐位还原（max(x,0)=x，min(x,1)=x）。T21 的
% 鼻孔软带加入 Fine 侧平台档位（.95 与 v3.1 nostrilProtection 峰值
% 对齐）；T22 的耳结构带同样进入 Fine 侧（.95，实测耳内 legacy
% alphaMap 均值 .322，Fine 门未饱和，进入 texture 通道才能保留耳轮/
% 沟槽细节）；鼻结构带不进 texture 通道（鼻梁 Fine 处理量保持 legacy）。
policyTexture = max(max(max(texture, .95 * detailBand), ...
    .95 * nostrilDetailBand), .95 * earStructureBand);
policyTexture = min(policyTexture, 1 - .55 * transitionBand);

% smoothSkinTexture L98：fineStructureGate = max(0, 1 - 4*structure)。
fineStructureGate = max(0, 1 - 4 * structure);
% Fine：hard 走生产原位的 max 合并，texture×structure 折叠进本字段。
% T20：texture 通道在 eye/lip 带内替换为 policyTexture。
smoothingFine = 1 - (1 - policyTexture) .* fineStructureGate;
% Mid：midStructureGate（=fineStructureGate）与 noseMidGate 的静态满档
% 快照（生产 noseMidGate = 1 - .50*nose.*alphaCurve，alphaCurve 归
% effect-strength 侧）。T20：eye/lip 带内补中频保护。T21：鼻孔软带
% （.90，identity 邻域）与结构带（.85，光影结构）补中频保护。
% T22：耳结构带补 .90（耳轮/耳甲腔沟槽落在 Mid 频段）。
smoothingMid = max(max(max(max(1 - fineStructureGate .* (1 - .50 * nose), ...
    .90 * detailBand), .30 * transitionBand), ...
    max(.90 * nostrilDetailBand, .85 * noseStructureBand)), ...
    .90 * earStructureBand);

% repairSkinBlemishes L48-51：strongStructure 与 structureGate 上限，
% 零瑕疵参考点为 min(1 - structure, 1 - .65*strongStructure)。
strongStructure = smoothStep(structure, .70, .90) .* ...
    double(bwdist(hard >= .999) <= 3);
structureGateRepair = min(1 - structure, 1 - .65 * strongStructure);
% repairSkinBlemishes L97-100：textureGate = 1 - texture 线性作用于
% fineWeight/mediumWeight/chromaWeight。T20：texture 通道同上替换。
repairFine = 1 - structureGateRepair .* (1 - policyTexture);
% repair 侧 noseMidGate = 1 - .50*nose（L78，无 alphaCurve，纯静态）。
% T20：eye/lip 带内补中频保护（与 smoothingMid 同族）。T21：鼻部带同上。
% T22：耳结构带同上（.90）。
repairMid = max(max(max(max(1 - structureGateRepair .* (1 - .50 * nose) .* ...
    (1 - policyTexture), .90 * detailBand), .30 * transitionBand), ...
    max(.90 * nostrilDetailBand, .85 * noseStructureBand)), ...
    .90 * earStructureBand);

% evenSkinLuminance L42/L88-93：featureProtection = max(texture, chroma)。
% T20：texture 通道同上替换（过渡带 cap 打开亮度均衡的处理量）。
% T21：结构带内补低频参考保护（.80，鼻梁低频明暗是立体感主载体）。
% T22：耳结构带内补同档保护（.80，耳轮亮脊/耳甲腔暗谷的低频对比）。
baseLuminance = max(max(1 - (1 - structure) .* (1 - max(policyTexture, chroma)), ...
    .80 * noseStructureBand), .80 * earStructureBand);

% normalizeSkinTone L77-78：featureGate = 1 - .78*chroma（主分支）。
% T20：唇细节带内补唇色 identity 保护。T21：不追加鼻部项——鼻部无
% identity 色度语义，肤色变化与脸颊连续。T22：同样不追加耳部项——
% 耳部无 identity 色度语义，耳-颊 tone 差与 legacy 逐位相同。
tone = max(1 - (1 - structure) .* (1 - .78 * chroma), ...
    .90 * lipDetailBand);

% applySkinWhitening L53-57/L61：脸部浅退让 1 - .10*structure 与
% featureSetback = 1 - whitening。T20：细节带内补假白光晕退让。
% T21：鼻孔软带内补同档退让（防鼻孔边缘假白光晕）；鼻皮肤不设退让。
% T22：耳部不设任何退让——耳-颊 whitening 差与 legacy 逐位相同，
% 不引入耳-颊异色块（工单第 2 步：肤色连续）。
structureGateWhitening = 1 - structure;
faceSkinSupport = faceSkin >= .5;
structureGateWhitening(faceSkinSupport) = ...
    1 - .10 * structure(faceSkinSupport);
whiteningField = max(1 - structureGateWhitening .* (1 - whitening), ...
    max(.85 * detailBand, .85 * nostrilDetailBand));

% T30 纯 policy 带（激活载体，与上面的 legacy 折叠式解耦）。
%   语义：某通道相对 legacy 追加的保护量，取值 [0,1]；消费侧唯一读取
%   方式为 gate := gate .* (1 - band)。带值只由 T20/T21/T22 的证据带
%   合成，不再折叠进 legacy 表达式，也不再从折叠快照反解。缺省/
%   partial evidence 时全零（各带下支撑点以上才有非零值），
%   gate .* 1 逐位还原 legacy。
%   逐通道来源（与各 stage 折叠快照里 max 项一一对应）：
%     regionBandFine —— texture 通道替换量，作用于 repair.textureGate
%       （fineWeight/mediumWeight/chromaWeight 与共享
%       referenceReliability）。eye/lip detail 带、nostril 软带、ear
%       结构带各取 .95（检测细节档位，与各 stage 快照同档）。
%       过渡带 cap（1-.55*transitionBand）不进入本带：它是"打开处理
%       量"的负向 cap，而本带语义为非负追加保护量；该 cap 已由
%       smoothingFine 快照直接消费生效。
%     regionBandMid —— Mid 专属追加量（texture 通道之外的鼻部/过渡
%       项），作用于 repair.noseMidGate（仅 mediumWeight）。刻意不含
%       detail/nostril/ear 项：这三项的 Mid 保护在折叠快照里由
%       policyTexture（= 本层 regionBandFine）承载，重复放进 noseMidGate
%       会让 mediumWeight 同时乘 (1-bandFine) 与 (1-bandMid) 而双重
%       计入（实测 detail 带内会从 .95 档位跌到 .9975 保护）。
%       .30*transitionBand 维持眼窝/唇周中频明暗连续；.85*noseStructure
%       给鼻梁/鼻翼光影结构保留 >=15% 中频处理量。
%     regionBandBase —— evenSkinLuminance 的 regionBandGate（逐像素
%       supportMap 门，不进全局参考卷积）。detail/nostril/ear 取 .95
%       （与 baseLuminance 快照的 policyTexture 通道同档），
%       noseStructure 取 .80（鼻梁低频明暗，保留 >=20% 亮度均衡量）。
%     regionBandTone —— normalizeSkinTone 主分支 featureGate。只有唇
%       detail 带（唇色是 identity 色度）；鼻/耳无 identity 色度语义。
%     regionBandWhitening —— applySkinWhitening.featureGate。eye/lip
%       detail 带与 nostril 软带各 .85（防假白光晕），与 whitening 快照
%       同档；耳部不设退让（耳-颊肤色连续）。
regionBandFine = max(max(.95 * detailBand, .95 * nostrilDetailBand), ...
    .95 * earStructureBand);
regionBandMid = max(.30 * transitionBand, .85 * noseStructureBand);
regionBandBase = max(max(.95 * detailBand, .95 * nostrilDetailBand), ...
    max(.95 * earStructureBand, .80 * noseStructureBand));
regionBandTone = .90 * lipDetailBand;
regionBandWhitening = max(.85 * detailBand, .85 * nostrilDetailBand);

% T31 规范门发布（上位契约第 2 节）：
%   target.* —— 该像素能不能被修改（逐像素修改门）；
%   support.* —— 该像素能不能作为邻域计算的参考样本。
% 两者必须分离：进入邻域/参考统计的门（support.*）与逐像素修改门
% （target.*）解耦，使 referenceWeight/referenceReliability 不被 target
% 门扰动。target.* 的零带值逐位等于 T07 折叠快照；support.* 的零带值
% 逐位等于 T30 之前 consumer 侧同名基准门（见文首"字段语义分三类"）。
% 同一语义只保留一个规范字段：T07 的扁平折叠名 smoothingFine/
% smoothingMid/repairFine/repairMid 已被 target.* 取代并删除。
protection = struct( ...
    'hard', hard, ...
    'target', struct( ...
    'smoothingFine', clamp01(smoothingFine), ...
    'smoothingMid', clamp01(smoothingMid), ...
    'repairFine', clamp01(repairFine), ...
    'repairMid', clamp01(repairMid)), ...
    'support', struct( ...
    'smoothingFine', clamp01(max(max(texture, structure), hard)), ...
    'smoothingMid', clamp01(min(4 * structure, 1)), ...
    'repairFine', clamp01(texture), ...
    'repairMid', clamp01(structure)), ...
    'noseMidProtection', clamp01(.50 * nose), ...
    'baseLuminance', clamp01(baseLuminance), ...
    'tone', clamp01(tone), ...
    'whitening', clamp01(whiteningField), ...
    'regionBandFine', clamp01(regionBandFine), ...
    'regionBandMid', clamp01(regionBandMid), ...
    'regionBandBase', clamp01(regionBandBase), ...
    'regionBandTone', clamp01(regionBandTone), ...
    'regionBandWhitening', clamp01(regionBandWhitening));
end

function [eyeField, lipField] = readEyeLipEvidence(policyEvidence, imageSize)
%READEYELIPEVIDENCE 从 policy evidence 中读取 eye/lip 语义字段。
%   缺省输入、空结构或缺少 periocular/lip 字段（partial V4）时返回零
%   矩阵（零带 → legacy 逐位还原）；字段存在但类型/尺寸/取值非法时
%   fail-fast，不静默修正。
emptyField = zeros(imageSize);
if isempty(policyEvidence)
    eyeField = emptyField;
    lipField = emptyField;
    return;
end
if ~isstruct(policyEvidence) || ~isscalar(policyEvidence)
    error('masks:InvalidEvidence', ...
        'policyEvidence 必须是标量 evidence 结构或为空。');
end
eyeField = readEvidenceField(policyEvidence, 'periocular', imageSize);
lipField = readEvidenceField(policyEvidence, 'lip', imageSize);
end

function [nostrilDetailBand, noseStructureBand] = readNoseBands( ...
    policyEvidence, beautyMasks, imageSize)
%READNOSEBANDS 从 policy evidence 读取鼻部语义字段并构建 T21 两条带。
%   缺省输入、空结构或缺少 nostril/noseStructure 字段（partial V4）时
%   返回零带（→ legacy 逐位还原）；字段存在但类型/尺寸/取值非法时
%   fail-fast，不静默修正。nostril 软带几何：nostrilEdge =
%   max(0, 1 - bwdist(nostrilCore)/(r+1))，r = min(4, max(2,
%   round(.006*faceScale)))——与 buildTextureProtectionMask 的
%   nostrilProtection 同一 radius 公式与 footprint（2--5px 软带，
%   非大半径膨胀）；faceScale 取自 beautyMasks.faceScale，nostril
%   证据非零而 faceScale 缺失/非法时 fail-fast。
emptyField = zeros(imageSize);
nostrilField = emptyField;
noseStructureField = emptyField;
if isempty(policyEvidence)
    nostrilDetailBand = emptyField;
    noseStructureBand = emptyField;
    return;
end
if ~isstruct(policyEvidence) || ~isscalar(policyEvidence)
    error('masks:InvalidEvidence', ...
        'policyEvidence 必须是标量 evidence 结构或为空。');
end
nostrilField = readEvidenceField(policyEvidence, 'nostril', imageSize);
noseStructureField = readEvidenceField(policyEvidence, 'noseStructure', ...
    imageSize);
nostrilCore = nostrilField >= .999;
if any(nostrilCore(:))
    faceScale = readFaceScale(beautyMasks);
    nostrilRadius = min(4, max(2, round(.006 * faceScale)));
    nostrilEdge = max(0, 1 - bwdist(nostrilCore) ./ (nostrilRadius + 1));
else
    nostrilEdge = emptyField;
end
nostrilDetailBand = smoothStep(nostrilEdge, .40, .80);
noseStructureBand = smoothStep(noseStructureField, .15, .50);
end

function earStructureBand = readEarBands(policyEvidence, imageSize)
%READEARBANDS 从 policy evidence 读取 T22 耳部结构字段并构建结构带。
%   缺省输入、空结构或缺少 earStructure 字段（partial V4）时返回零带
%   （→ legacy 逐位还原）；字段存在但类型/尺寸/取值非法时 fail-fast，
%   不静默修正。带的下/上支撑点（.05/.30）依据真实图 77 的 earStructure
%   分布（P25=.004、P50=.144、P75=.570）选取：下支撑点≈P31 保证平坦耳
%   皮肤零带、保持 processability，上支撑点≈P60 让高于中位数的耳结构
%   （耳轮脊线/耳甲腔壁/对耳轮褶皱）进入满档；earStructure 本身已被
%   ear 语义支持域约束，故带在 ear semantic 支持域外严格为 0。
if isempty(policyEvidence)
    earStructureBand = zeros(imageSize);
    return;
end
if ~isstruct(policyEvidence) || ~isscalar(policyEvidence)
    error('masks:InvalidEvidence', ...
        'policyEvidence 必须是标量 evidence 结构或为空。');
end
earStructureField = readEvidenceField(policyEvidence, 'earStructure', ...
    imageSize);
earStructureBand = smoothStep(earStructureField, .05, .30);
end

function faceScale = readFaceScale(beautyMasks)
%READFACESCALE 读取鼻孔软带几何所需的脸部尺度（fail-fast 校验）。
if ~isfield(beautyMasks, 'faceScale')
    error('masks:InvalidMasks', ...
        'Beauty Masks 缺少 faceScale，无法构建鼻孔软带几何。');
end
value = beautyMasks.faceScale;
if ~isnumeric(value) && ~islogical(value)
    error('masks:InvalidMasks', 'Beauty Masks 字段 faceScale 无效。');
end
value = double(value);
if ~isscalar(value) || ~isreal(value) || ~isfinite(value) || value <= 0
    error('masks:InvalidMasks', 'Beauty Masks 字段 faceScale 无效。');
end
faceScale = value;
end

function value = readEvidenceField(evidence, name, imageSize)
if ~isfield(evidence, name) || isempty(evidence.(name))
    value = zeros(imageSize);
    return;
end
value = evidence.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~isequal(size(value), imageSize) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || ...
        any(value(:) > 1)
    error('masks:InvalidEvidence', ...
        'evidence 字段 %s 的尺寸或取值无效。', name);
end
value = double(value);
end

function value = readMask(beautyMasks, name)
value = beautyMasks.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isreal(value) || ...
        ~ismatrix(value) || isempty(value) || ...
        any(~isfinite(value(:))) || any(value(:) < 0) || any(value(:) > 1)
    error('masks:InvalidMasks', ...
        'Beauty Masks 字段 %s 的类型、尺寸或取值无效。', name);
end
value = double(value);
end

function value = smoothStep(inputValue, low, high)
t = min(max((double(inputValue) - low) / max(high - low, eps), 0), 1);
value = t .^ 2 .* (3 - 2 * t);
end

function value = clamp01(value)
value = min(max(double(value), 0), 1);
end
