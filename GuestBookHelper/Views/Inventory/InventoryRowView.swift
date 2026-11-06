import SwiftUI

struct InventoryRowView: View {
    var item: InventoryItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.categorySoftColor(item.displayCategory))
                    .frame(width: 40, height: 40)
                Image(systemName: AppTheme.categorySymbol(item.displayCategory))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.categoryColor(item.displayCategory))
                if item.transactionType == .sellout {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AppTheme.sold)
                        .frame(width: 10, height: 2)
                        .rotationEffect(.degrees(-45))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.displayModel)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(AppTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    StatusBadge(type: item.transactionType)
                }

                HStack(spacing: 5) {
                    Text(item.displayCapacity)
                    Text("·")
                        .foregroundColor(AppTheme.tertiary)
                    Text(item.displayColor)
                    if item.condition != .unknown {
                        Text("·")
                            .foregroundColor(AppTheme.tertiary)
                        ConditionBadge(condition: item.condition, compact: true)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundColor(AppTheme.secondary)
                .lineLimit(1)

                HStack(spacing: 5) {
                    Text(item.serialNumber)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.tertiary)
                    Spacer(minLength: 4)
                    if item.hasNoRecordSaleTag {
                        Text("不计库存")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(AppTheme.warning)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(AppTheme.warningSoft))
                    }
                    if !item.presentInLatestEOH && item.transactionType != .sellout && item.transactionType != .transferOut {
                        Text("历史")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(AppTheme.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(AppTheme.surfaceMuted))
                    }
                }

                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 8))
                    Text(dateLabel)
                        .font(.system(size: 9.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .foregroundColor(AppTheme.tertiary)

                if !item.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(item.tags.prefix(2))) { tag in
                            TagChip(tag: tag)
                        }
                        if item.tags.count > 2 {
                            Text("+\(item.tags.count - 2)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(AppTheme.tertiary)
                        }
                    }
                    .padding(.top, 1)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(AppTheme.tertiary.opacity(0.7))
                .padding(.top, 4)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(AppTheme.line.opacity(0.9), lineWidth: 0.7)
                )
        )
        .contentShape(Rectangle())
    }

    private var dateLabel: String {
        if item.transactionType == .returned, let date = item.returnedDate {
            return "退货 \(DateFormatter.gbDateTime.string(from: date))"
        }
        if item.transactionType == .transferOut, let date = item.transferOutDate {
            return "出库 \(DateFormatter.gbDateTime.string(from: date))"
        }
        if item.transactionType == .sellout, let date = item.selloutDate {
            return "售出 \(DateFormatter.gbDateTime.string(from: date))"
        }
        if let date = item.transferInDate {
            return "入库 \(DateFormatter.gbDateTime.string(from: date))"
        }
        if let date = item.returnedDate {
            return "退货 \(DateFormatter.gbDateTime.string(from: date))"
        }
        if let date = item.transferOutDate {
            return "出库 \(DateFormatter.gbDateTime.string(from: date))"
        }
        if let date = item.selloutDate {
            return "售出 \(DateFormatter.gbDateTime.string(from: date))"
        }
        return "日期未知"
    }
}
