import LingpaoCore
import SwiftUI

/// 自适应均衡排布网格：依据元素数量按 `BalancedGridPartitioner` 对称拆行，彻底杜绝数量不整时的孤单空白格
public struct BalancedActionGrid<Item: Identifiable, Cell: View>: View {
    public let items: [Item]
    public let maxColumns: Int
    public let spacing: CGFloat
    @ViewBuilder public let content: (Item) -> Cell

    public init(
        items: [Item],
        maxColumns: Int,
        spacing: CGFloat = 10,
        @ViewBuilder content: @escaping (Item) -> Cell
    ) {
        self.items = items
        self.maxColumns = maxColumns
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        let rowCounts = BalancedGridPartitioner.partition(count: items.count, maxColumns: maxColumns)
        let rows: [[Item]] = {
            var res: [[Item]] = []
            var offset = 0
            for c in rowCounts {
                let end = min(offset + c, items.count)
                if offset < end {
                    res.append(Array(items[offset..<end]))
                }
                offset = end
            }
            return res
        }()

        VStack(spacing: spacing) {
            ForEach(rows.indices, id: \.self) { rowIdx in
                HStack(spacing: spacing) {
                    ForEach(rows[rowIdx]) { item in
                        content(item)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// 主页「快捷控制」自定义编辑器（支持功能增删、顺序微调与恢复默认）
public struct HomeQuickControlEditorSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var selected: [HomeQuickAction] = []

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)
        let available = HomeQuickAction.allCases.filter { !selected.contains($0) }

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("当前快捷控制（\(selected.count) 项）")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.ink)
                            Spacer()
                            Button("恢复默认") {
                                withAnimation(.spring(duration: 0.25)) {
                                    selected = HomeQuickAction.defaults
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.good)
                        }

                        if selected.isEmpty {
                            Text("至少保留 1 个快捷按钮，也可从下方添加")
                                .font(.caption)
                                .foregroundStyle(palette.secondary)
                                .padding(.vertical, 12)
                        } else {
                            ForEach(Array(selected.enumerated()), id: \.element.id) { idx, action in
                                HStack(spacing: 10) {
                                    Image(systemName: action.staticIcon)
                                        .font(.subheadline)
                                        .foregroundStyle(palette.good)
                                        .frame(width: 24)
                                    Text(action.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(palette.ink)
                                    Spacer()

                                    reorderButtons(index: idx, count: selected.count, palette: palette) { delta in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selected.swapAt(idx, idx + delta)
                                        }
                                    }

                                    Button {
                                        guard selected.count > 1 else { return }
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selected.remove(at: idx)
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(selected.count > 1 ? palette.danger : palette.inactive)
                                    }
                                    .disabled(selected.count <= 1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.background))
                            }
                        }
                    }
                    .lingpaoCard(padding: 14)

                    if !available.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("添加更多快捷功能")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.ink)

                            BalancedActionGrid(items: available, maxColumns: 3, spacing: 8) { action in
                                Button {
                                    withAnimation(.spring(duration: 0.25)) {
                                        selected.append(action)
                                    }
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: action.staticIcon)
                                            .font(.system(size: 16, weight: .semibold))
                                            .frame(height: 18)
                                        Text("+ \(action.displayName)")
                                            .font(.caption2.weight(.medium))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 54)
                                    .padding(.horizontal, 4)
                                    .foregroundStyle(palette.ink)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.background))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .lingpaoCard(padding: 14)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 26)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("编辑主页快捷控制")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        var prefs = viewModel.layoutPreferences
                        prefs.homeQuickActions = selected
                        viewModel.saveLayoutPreferences(prefs)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            selected = viewModel.layoutPreferences.homeQuickActions
        }
    }
}

/// 控车页面「分组排序 + 各组功能增删」统一自定义抽屉
public struct CabinLayoutEditorSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var prefs: ControlLayoutPreferences = ControlLayoutPreferences.default()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let palette = LingpaoPalette.forScheme(colorScheme)

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // 区块 1：三组卡片显示顺序
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("控车卡片排序")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(palette.ink)
                            Spacer()
                            Button("恢复默认") {
                                withAnimation(.spring(duration: 0.25)) {
                                    prefs = ControlLayoutPreferences.default(for: viewModel.currentCarProfile.displayName)
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.good)
                        }

                        ForEach(Array(prefs.cabinGroupOrder.enumerated()), id: \.element.id) { idx, group in
                            HStack(spacing: 10) {
                                Text("\(idx + 1)")
                                    .font(.caption2.weight(.bold))
                                    .frame(width: 22, height: 22)
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(palette.good))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(palette.ink)
                                    Text(group.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondary)
                                }

                                Spacer()

                                reorderButtons(index: idx, count: prefs.cabinGroupOrder.count, palette: palette) { delta in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        prefs.cabinGroupOrder.swapAt(idx, idx + delta)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.background))
                        }
                    }
                    .lingpaoCard(padding: 14)

                    // 区块 2：空调快捷模式功能勾选
                    sectionToggleGrid(
                        title: "空调快捷模式（\(prefs.climateQuickActions.count)/\(ClimateQuickAction.allCases.count)）",
                        allItems: ClimateQuickAction.allCases,
                        selectedItems: $prefs.climateQuickActions,
                        label: { $0.displayName },
                        icon: { $0.icon },
                        palette: palette
                    )

                    // 区块 3：门窗与车身控制功能勾选（包含方向盘加热、前后备箱、二/三排模式与侧滑门）
                    sectionToggleGrid(
                        title: "门窗与车身控制（\(prefs.bodyHardwareActions.count)/\(BodyHardwareAction.allCases.count)）",
                        allItems: BodyHardwareAction.allCases,
                        selectedItems: $prefs.bodyHardwareActions,
                        label: { $0.displayName },
                        icon: { $0.staticIcon },
                        palette: palette
                    )

                    // 区块 4：定时预约功能勾选
                    sectionToggleGrid(
                        title: "定时预约（\(prefs.comfortScheduleActions.count)/\(ComfortScheduleAction.allCases.count)）",
                        allItems: ComfortScheduleAction.allCases,
                        selectedItems: $prefs.comfortScheduleActions,
                        label: { $0.displayName },
                        icon: { $0.icon },
                        palette: palette
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 26)
            }
            .background(palette.background.ignoresSafeArea())
            .navigationTitle("自定义控车布局")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        viewModel.saveLayoutPreferences(prefs)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            prefs = viewModel.layoutPreferences
        }
    }

    @ViewBuilder
    private func sectionToggleGrid<Item: Identifiable & Equatable>(
        title: String,
        allItems: [Item],
        selectedItems: Binding<[Item]>,
        label: @escaping (Item) -> String,
        icon: @escaping (Item) -> String,
        palette: LingpaoPalette
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.ink)
            toggleGridContent(
                allItems: allItems,
                selectedItems: selectedItems,
                label: label,
                icon: icon,
                palette: palette
            )
        }
        .lingpaoCard(padding: 14)
    }

    @ViewBuilder
    private func toggleGridContent<Item: Identifiable & Equatable>(
        allItems: [Item],
        selectedItems: Binding<[Item]>,
        label: @escaping (Item) -> String,
        icon: @escaping (Item) -> String,
        palette: LingpaoPalette
    ) -> some View {
        BalancedActionGrid(items: allItems, maxColumns: 3, spacing: 8) { item in
            let isIncluded = selectedItems.wrappedValue.contains(item)
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if let idx = selectedItems.wrappedValue.firstIndex(of: item) {
                        selectedItems.wrappedValue.remove(at: idx)
                    } else {
                        selectedItems.wrappedValue.append(item)
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    HStack {
                        Spacer()
                        Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(isIncluded ? palette.good : palette.inactive)
                    }
                    Image(systemName: icon(item))
                        .font(.system(size: 15, weight: .semibold))
                        .frame(height: 18)
                    Text(label(item))
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .foregroundStyle(isIncluded ? palette.ink : palette.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isIncluded ? palette.good.opacity(0.08) : palette.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isIncluded ? palette.good : palette.line, lineWidth: isIncluded ? 1.2 : 0.7)
                        )
                )
            }
            .buttonStyle(.plain)
        }
    }
}

@ViewBuilder
private func reorderButtons(
    index: Int,
    count: Int,
    palette: LingpaoPalette,
    onMove: @escaping (Int) -> Void
) -> some View {
    HStack(spacing: 6) {
        Button {
            onMove(-1)
        } label: {
            Image(systemName: "arrow.up.circle")
                .font(.subheadline)
                .foregroundStyle(index > 0 ? palette.ink : palette.inactive.opacity(0.5))
        }
        .disabled(index <= 0)

        Button {
            onMove(1)
        } label: {
            Image(systemName: "arrow.down.circle")
                .font(.subheadline)
                .foregroundStyle(index < count - 1 ? palette.ink : palette.inactive.opacity(0.5))
        }
        .disabled(index >= count - 1)
    }
    .buttonStyle(.plain)
}
