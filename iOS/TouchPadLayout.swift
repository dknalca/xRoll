import CoreGraphics

/// Calcula el espacio disponible para la rejilla táctil durante la práctica.
struct TouchPadControlSizing {
    let size: CGSize
    let columns: Int

    init(padCount: Int, availableWidth: CGFloat, bodyHeight: CGFloat, sideBySide: Bool) {
        let maximumColumns = Self.maximumColumns(padCount: padCount, sideBySide: sideBySide)
        let grid = TouchPadGridLayout(count: padCount, maximumColumns: maximumColumns)
        let widthLimit: CGFloat = sideBySide ? (padCount <= 3 ? 200 : 320) : 440
        let reservedWidth: CGFloat = sideBySide ? 280 : 12
        let width = max(0, min(widthLimit, availableWidth - reservedWidth))
        let cellHeightLimit: CGFloat = sideBySide ? 120 : 104
        let preferredHeight = CGFloat(grid.rows) * min(cellHeightLimit, width / CGFloat(grid.columns))
        let heightLimit = sideBySide ? bodyHeight - 36 : min(bodyHeight * 0.42, bodyHeight - 206)
        size = CGSize(width: width, height: max(0, min(heightLimit, preferredHeight)))
        columns = grid.columns
    }

    private static func maximumColumns(padCount: Int, sideBySide: Bool) -> Int {
        guard sideBySide else { return 4 }
        if padCount <= 3 { return 1 }
        if padCount <= 6 { return 2 }
        return 3
    }
}

/// Geometría virtual: no reutiliza las coordenadas físicas de Equipo. Dibujo,
/// hit testing y accesibilidad usan exactamente las mismas celdas compactas.
struct TouchPadGridLayout {
    let count: Int
    var maximumColumns = 4
    var columns: Int {
        min(max(1, maximumColumns), preferredColumns)
    }
    private var preferredColumns: Int {
        if count <= 3 { return max(1, count) }
        if count <= 4 { return 2 }
        if count <= 9 { return 3 }
        return 4
    }
    var rows: Int { max(1, (count + columns - 1) / columns) }

    func frame(at index: Int, in bounds: CGRect) -> CGRect {
        guard index >= 0, index < count else { return .zero }
        let row = index / columns
        let itemsInRow = min(columns, count - row * columns)
        let width = bounds.width / CGFloat(itemsInRow)
        let height = bounds.height / CGFloat(rows)
        return CGRect(x: bounds.minX + CGFloat(index % columns) * width,
            y: bounds.minY + CGFloat(row) * height, width: width, height: height)
    }
}
