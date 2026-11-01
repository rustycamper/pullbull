import CoreGraphics

/// Where the Status picker opens in the popover: below its row, above it when there's no room below,
/// and always wholly on screen.
public enum StatusPickerPlacement {
    /// The picker's frame for its row `anchor` (nil when the row isn't on screen: near the top) and its
    /// measured `height`, in a popover of size `container`.
    public static func frame(anchor: CGRect?, height: CGFloat, in container: CGSize, width: CGFloat = 300) -> CGRect {
        let margin: CGFloat = 4
        let row = anchor ?? CGRect(x: 0, y: 40, width: container.width, height: 0)
        let width = min(width, container.width - 20)
        let height = min(height, container.height - 2 * margin)
        let x = min(max(row.minX + 12, 10), container.width - width - 10)
        let below = row.maxY + margin
        let above = row.minY - height - margin
        let y = if below + height <= container.height - margin {
            below
        } else if above >= margin {
            above
        } else {
            container.height - height - margin
        }
        return CGRect(x: x, y: min(max(y, margin), container.height - height - margin), width: width, height: height)
    }
}
