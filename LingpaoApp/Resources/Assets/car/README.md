# 多车型共享车图层

正式资源为 `<id>/exterior.webp`、`<id>/interior.webp`（目前已接入 C16、C11、A10、B01、B10、C10、Lafa5/B05、A05、D19、D99、T03），逐层优先 WebP、其次同名 PNG；缺失、损坏或比例不符时逐层回退 Compose 矢量。C16 已于 2026-11-12 接入统一规格重出素材，三排为连续双座长排。

透明背景、同一正交俯视机位，车头朝上，画布 1200×2800 对应 240×560（1 单位 = 5 像素）。兼容同比例 PNG，绘制采用高质量过滤。`CarAssets.kt` 在 IO dispatcher 解码、按显示像素宽度选采样倍率，宽度不超过 1200；以尺寸桶缓存图片及效果，页面切换不重新解码。

## 座舱、座椅和点击

- `seat_labels.png`：8 位灰度标签，0 背景，1 主驾、2 副驾、3 二排左、4 二排右、5 三排左、6 三排右、7 二排中、8 三排中。
- 启动后台从原始标签生成每座 alpha 蒙版，原图 sigma 2.5px 羽化且限制在标签内部。后台按皮革像素生成 W3C Color 等效着色（保留原亮度，再叠淡 Screen），Android 8/API 26 也适用，不依赖 API 29 的 Color 混合模式。合成后的皮革颜色乘以真实蒙版 alpha 叠到原图，控制台不着色。
- 加热缺图回退 `#E0793A`，Color 强度 `0.20 + 0.08×档位`，Screen `#FF9A55`、`0.05 + 0.03×档位`；通风缺图使用 `#287DEB`、`0.32 + 0.16×档位`，Screen `#65A9FF`、`0.04 + 0.04×档位`，在座椅蒙版内保留皮革明暗。选中只在轮廓内 Screen 白 0.10，无描边、档位小点。
- `cabin_mask.png`：座舱灰度蒙版。空调开启时先铺全舱冷色（Color `#5E95F0` 0.38 + Screen `#A9C8FF` 0.07），再显示独立座椅状态，无虚线气流。
- `CarAssets.kt` 使用 `seatLabelRects()` 扫描该车型原始标签的精确包围盒，绘制与点击共用，不在枚举内写死坐标。新 C16 的六个标签由 `design/lingkong/car-masks/overrides/c16.json` 的搜索窗口生成；三排在原图 x=600 分区，中间没有通道。
- 方向盘优先使用每车配准的光效贴图；缺图才使用既有程序环形暖光。

## 可选资源

均对齐同一 1200×2800 画布，逐项优先 `fx/` 下 WebP、其次 PNG；缺失、损坏、比例不符或全透明时静默回退程序着色（座椅/方向盘）或跳过（灯光/折镜）。不修改原始文件。

- `<id>/fx/seat_<driver|passenger|r2l|r2r|r3l|r3r>_heat.webp`（C16 仅主驾）
- `<id>/fx/seat_<driver|passenger|r2l|r2r>_vent.webp`（C16 仅主驾）
- `c16/fx/wheel_heat.webp`
- `c16/fx/lights_glow_only.webp`
- `c16/fx/exterior_mirrors_folded.webp`

非座椅项也兼容 `c16/` 下同名 WebP/PNG。全部在 IO dispatcher 一次性解码、裁切并按尺寸桶缓存；先发布车内/车外主图，FX 随后到位。

座椅加热及方向盘柔光以 `inSampleSize=max(2, 主图采样倍率)` 解码；通风沿用主图采样倍率，保留细小蓝点。按 alpha>0 求包围盒并保留最多 2px 余量；只缓存包围盒内像素，通过 patch 的缩放倍率恢复主图坐标。普通 source-over 合成，1/2/3 档 alpha 分别为 0.33/0.66/1。有素材的加热模式不生成也不叠加程序着色；有通风贴图时直接显示交付贴图，缺图时使用对应档位的蒙版染色。新 C16 的主驾热／通风在接入时按 55px 内部距离做 smoothstep 渐淡，边缘乘 0.4、中心乘 1，最大 alpha 为 130／95；方向盘不做柔化。参数与公式见 `design/lingkong/car-masks/README.md`。选中提亮仍保留。

灯光按最大透明行间隙分成前后两条，各自裁切缓存。解锁/鸣笛寻车开始时淡入淡出两次（每次淡入 120ms、淡出 220ms、间隔 100ms），不持续循环；冷启动等待灯光资源到位后开始。后视镜图与主图逐像素比较，完整保留 alpha 差异，忽略同 alpha 的微小 RGB 编码误差（不透明度至少 128 时 RGB 任一通道差值 >24 才计入，低 alpha 的反预乘 RGB 不参与），左右各裁一块；在独立车外图层中仅替换这两块区域，550ms 淡化，透明轮廓也随之消失。所有可选整图裁切后立即 recycle，不保留第二幅完整车外图。

Debug 缓存完成后用 `CarBitmapMemory` 打印所有常驻车图 Bitmap 的 `allocationByteCount` 总和及各 FX patch 尺寸；计入两张主图、座椅选择/缺图回退、空调层和全部 FX，release 不打印。尾门/充电口没有单独图层。

## 姿态与充电

基础坐标和转场集中于 `CarPose`：首页 `(206,94,.97)`、控车 `(63,-30,1.1)`、充电 `(214,102,.82)`。充电姿态显示原始车外图，不给车身染色、不画电池块；左侧 x=-14 加约 4dp 的竖条，原车坐标 y=10..556，SOC 从底部向上填绿渐变，healthyChargeLimitSoc 同轴短刻度。未知电量不填充；充电中仅条顶缓慢呼吸，未充电静止。

正式充电入口为新 UI 二级页面，出行缩为地图定位点 `(239,176,.075)`，我的滑出至 `(430,94,.97)`；共用原有 800ms 位移与 550ms 图层动画。debug `DesignPreviewActivity` 支持 `--ez chargePose true`（可选 `--ei soc 67 --ei limit 90 --ez charging true`）；`--ef transition 0.5` 按 800ms 位移动画与 550ms 淡化动画的实际 easing 冻结共享车图的中间帧，供对齐截图，不改变正式切页动画。


Debug 离线动画验收可用 `--es previewAction lock|unlock|horn --ei actionDelayMs 2500`；`lock` 搭配 `--ez locked false` 从展开状态开始，`unlock` 默认从上锁状态开始。只改变预览状态，不调用真实车控。控车座椅 fixture 固定主驾热3、副驾热1、二排左通风2、方向盘热3，可用 `--ei tab 1` 和 `--ez dark true` 检查浅深色。

通风分档对照用 `--ei tab 1 --ei driverVent 1|2|3`（设置此参数时主驾加热默认关闭）；`--ei driverHeat 3 --ei driverVent 0` 为加热对照，省略参数保留原 fixture。参数只改变离线假数据。

C16 重出图的首页／控车页由 `carDisplayPose` 在 `CarLayer` 内适配可见区域：归一化车图横向范围为 13.3..226.7；首页显示宽 180dp，左缘 206、右缘 386，不进入左侧车况列；控车页姿态 `(75,18.4,1)`，车头从 y=28 开始、车尾在面板上方。首页／控车只改变 C16 的 UI 位置与缩放，透明包围盒适配算法仍完全共用，其他车型与其他页面的姿态不变。

## 登录主视觉与四页预览

登录页按上次已登录车型（无记录则选 C16），优先使用 `<id>/hero_3q_transparent.webp`，缺图或解码失败回退 `hero/c16_3q.webp`（透明 C16 前 3/4），最终回退既有 C16 俯视车外图。在 IO dispatcher 以 2 倍采样解码，不修改素材。登录页与其他页面共享浅深色 token。

离线 debug Activity 支持 `--ez charge true`（完整充电页）、`--ez charging true`（充电中）、`--ei tab 2`（出行）、`--ei tab 3`（我的）、`--ez login true`（未登录）、`--ez dark true`、`--ez noData true`（空能耗/位置）、`--ez loginReady true --ei countdown 30`（合成登录表单/倒计时）。所有回调仅更新 fixture 或打印标记，不发短信、不登录、不控车。登录预览初始勾选为 false。

出行累计长小数验收：`--ei tab 2 --es totalMileage 24057.88 --es totalEnergy 3947.123456 --es ownershipDays 45.6789`；小值用 `--es totalEnergy 45.6789`，大值用 `--es totalMileage 1234567 --es totalEnergy 1234567 --es ownershipDays 1234567`。累计里程/能耗四舍五入为整数、绝对值小于 100 时最多一位小数，天数为整数；数字与小号单位同基线、单行按实际列宽自动缩小。近 7 天与日均显示规则不变。

冻结姿态用 `--ef transition 0.25 --es transitionTo trip|me|charge`，可叠加目标页参数；这只是按相同 easing 采样的静态姿态。真实动画验证需从首页点导航或电量入口，并录取实际中间帧。旧的 `chargePose` 独立车图验收入口继续保留。


## 多车型接入（2026-11-11）

- `CarModelProfile.kt` 是车型 / 车身类型 / 布局表。车型识别复用底座 `VehicleAppearanceCatalog.canonicalModel()`；B05 使用 `lafa5/`，未知车型沿用底座回退规则。
- 每款素材放 `car/<小写车型 ID>/`，文件名仍为 `exterior.webp`、`interior.webp`、`seat_labels.png`、`cabin_mask.png`、`fx/*`，图片优先 WebP、其次 PNG。D19 七座独用 `interior_7.webp` 和 `seat_labels_7.png`；外观共用。七座座椅效果按自己的标签生成，不套用六座的可选座椅 FX。蒙版与外观必须使用同一画布。
- 座位按布局过滤，中心座位参与绘制与选择，不生成指令。座椅标签用于包围盒与蒙版，灰度值必须是标签整数，不可抗锯齿成其他标签。当前加载要求 3:7 画布比例，推荐 1200×2800。
- 缓存按车型 ID + 布局 + 尺寸桶隔离；切换车型时立即清空旧图状态。绝不借用其他车型的素材。
- 外观透明通道包围盒按 C16 的车身范围等比适配，所有车型（含新 C16）的同画布图片、效果、点击区域共用变换。充电条继续使用原页面轴。
- 缺图走该车身类型的矢量轮廓（SUV / 轿车 / 两厢 / MPV / 微型），按布局生成座位；具有座椅热 / 通风、空调、折镜与闪灯回退。A05 的车身与五座布局暂定，待核对。
- 新车型交付时补齐上述素材即可，不改 UI 代码。规格见 `design/lingkong/car-art-spec.md`。座舱和座椅蒙版仍需交付时生成，不会从一张写实图自动识别座位。

Debug 离线预览：`--es model c11 --ei tab 1`；`--es model d19 --es layout 7`（也接受 `2+3+2` / `6` / `2+2+2`）；`--es model d99`；`--es model t03 --ez dark true`；增程 `--ez rangeExtender true` 或 `--es power range_extender`。只改变预览 fixture，不调用接口、不创建 SessionStore，也不保存布局偏好。正式入口 D19「我的 → 车辆 → 座椅布局」保存 UI 偏好到 SessionStore 既有的 `leap_app_preferences` 文件，键为 `lingkong_seat_layout_d19`，不读写车辆业务记录。

## 可复用接入与 C11（2026-11-11）

使用 `python3 design/lingkong/car-masks/ingest_car.py <id> <交付目录>`，详见 `design/lingkong/car-masks/README.md`。尺寸/透明通道/交付 hash/布局校验 → 有损 WebP quality 85 → 座椅和座舱 L 蒙版 → `.ai/reports/` 叠加预览，一条命令完成。没有可靠自动定位时，用每车型 JSON 窗口并在窗口内按皮革轮廓收边；C16 使用重新审阅的六座窗口，和其他车型一样完整接入。

C11 已接入 SUV、2+3 五座，与交付官方参数“5门5座”、车长/宽/高 4780/1905/1658 mm 及 `verification.json` 一致，无需修改档案。后排左/中/右标签分别 3/7/4。包括两张主图、座椅/座舱蒙版、灯带、折镜与独立定位的方向盘暖光。主图约 120–140 KiB，与 C16 同为百 KiB 量级；全画布 FX 由现有加载器裁片缓存。

车型登录主视觉命名 `<id>/hero_3q_transparent.webp`。正式 UI 在已登录且有车型名称时，只把车型 ID 保存到独立 `lingkong_car_art` UI 偏好（键 `last_logged_in_model`）；退出后保留，登录页依次尝试该车型主视觉、现有 `car/hero/c16_3q.webp`，再回退现有 C16 俯视图。缺失、损坏、无记录均可回退，不保存账号信息、不改变登录业务。

Debug 新增 `--ei passengerHeat 0 --ei passengerVent 3 --ei rearLeftHeat 2 --ei rearLeftVent 0`，与 `--ei driverHeat 3` 组合检查 C11 三个独立效果；它们只注入 fixture，不能据此推断真实 C11 支持二排加热。`--ez login true --es lastModel c11` 直接预览 C11 主视觉；省略 `lastModel` 无记录，`--es lastModel d19` 检查缺图回退。显式 `--es persistHeroModel c11 --ez useSavedHero true --ez login true` 在模拟器中仅保存该 UI 车型 ID，再杀进程用 `--ez useSavedHero true --ez login true` 检查跨进程持久化。普通 debug 预览仍不读写偏好，不创建会话。

## 第二批写实车图（2026-11-11）

A10、B01、B10、C10、Lafa5（B05）均已接入 2+3 五座素材，后排左/中/右使用 3/7/4 标签。每款含车外、车内、登录主视觉、座椅/座舱蒙版、灯光、折镜及独立定位的方向盘暖光；仍使用原有加载器与离线接入脚本，无业务逻辑改动。

已核对交付 `official-parameters.json` 与 `verification.json`：A10/B10/C10 为五门五座、B01 为四门五座、Lafa5 为五门五座掀背车，与现有 SUV/SEDAN/HATCHBACK 档案无冲突。官方 JSON 未单列 A10/B10/C10 的 SUV 分类字段，分类沿用现有档案及交付外形，不把门数本身当作 SUV 证明。

各车连通后排长椅使用 `design/lingkong/car-masks/overrides/<id>.json` 的独立窗口分区，窗口内沿皮革亮度和连通轮廓生成标签。模拟器统一使用主驾加热 3、副驾通风 3、二排左加热 2 的 debug fixture 检查贴合；该 fixture 不代表真实配置支持这些功能。截图、输入/输出校验和与 C16/C11 回归证据见 `.ai/reports/shots-20261111-153212/`。

## 第三批与 D19 双布局（2026-11-11）

A05 为五门五座掀背车（交付参数 4200×1800 mm、2+3），已去掉档案中的待核对注释。D19 为六座 2+2+2 / 七座 2+3+2；D99 为 MPV 2+2+3，二排保留独立座椅之间的通道，三排左/中/右标签为 5/8/6；T03 为四座 2+2，使用交付的 3620×1652 mm 外形和现有透明包围盒自适应。T03 交付资料不能独立确认最新国内改款年款，折镜图仅为机械折叠姿态，不表示支持电动折叠。

先导入 D19 默认六座，再运行七座：

```bash
python3 design/lingkong/car-masks/ingest_car.py d19 /path/to/cars/d19
python3 design/lingkong/car-masks/ingest_car.py d19 /path/to/cars/d19 --layout SEVEN
```

默认读取 `overrides/d19.json`；七座读取 `overrides/d19_7.json`，也可用 `--override` 显式指定。七座交付 metadata 仍登记默认布局 2+2+2，脚本只在同时登记 `files.interior_7` 和 `source_sha256[interior_7.png]` 时允许这个已知变体，源文件 hash 仍全部验证。七座仅写入 `interior_7.webp`、`seat_labels_7.png`、`cabin_mask_7.png`，不重新编码或覆盖共用的外观、灯光、折镜、方向盘与六座资源。`CarModelProfile` 的三个命名方法与按布局缓存的加载器一起切换车内图、标签、空调蒙版和座椅列表，缺失七座资源时不借用六座蒙版。

每套车内使用独立的人工核对窗口；D19 六座二排效果限制到椅背和坐垫，避开扶手旁地板。A05/D19/T03 阈值为 26，D99 为 20；亮饰边仍由座舱亮度上限排除。逐款叠加预览、模拟器截图、资源体积与回归证据放在 `.ai/reports/shots-20261111-155431/`。

debug 预览可显式传 `--ei thirdLeftHeat 1`（同时 `--ei tab 1`，座椅页），用生产加载器生成的三排左座椅热色 patch 验证贴合。它仅存在于 `src/debug`，不增加真实三排状态或指令；底座当前无三排加热遥测，正式 UI 仍显示暂不支持。普通预览不启用此叠层。前三个效果仍传 `--ei driverHeat 3 --ei passengerHeat 0 --ei passengerVent 3 --ei rearLeftHeat 2 --ei rearLeftVent 0`。所有舒适 fixture 仅验证图像，不表示真实车型配置。
