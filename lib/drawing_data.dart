import 'dart:ui';

/// 図形の種類
enum DrawingType {
  line, // 直線
  rectangle, // 矩形
  oval, // 楕円
  roundedRectangle, // 角丸矩形
  burst, // 破裂
  elbow, // L型線
  marker, // マーカー
  image, // 画像
  table, // テーブル (表)
}

/// 線の種類
enum LineStyle {
  solid, // 実線
  dotted, // 点線
  dashed, // 破線
  doubleLine, // 二重線
}

/// テキスト上の論理位置を表すクラス
/// (行番号, 文字列インデックス) + (微調整オフセット)
class AnchorPoint {
  int row; // 行番号 (0-based)
  int col; // 文字列インデックス (0-based)
  double dx; // col位置からの相対X座標 (比率: 0.0〜1.0)
  double dy; // row位置からの相対Y座標 (比率: 0.0〜1.0)

  AnchorPoint({
    required this.row,
    required this.col,
    this.dx = 0.0,
    this.dy = 0.0,
  });

  // コピー用
  AnchorPoint copyWith({int? row, int? col, double? dx, double? dy}) {
    return AnchorPoint(
      row: row ?? this.row,
      col: col ?? this.col,
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
    );
  }

  // JSON変換
  Map<String, dynamic> toJson() => {'row': row, 'col': col, 'dx': dx, 'dy': dy};

  factory AnchorPoint.fromJson(Map<String, dynamic> json) {
    return AnchorPoint(
      row: json['row'] as int,
      col: json['col'] as int,
      dx: (json['dx'] as num).toDouble(),
      dy: (json['dy'] as num).toDouble(),
    );
  }

  @override
  String toString() => 'Anchor($row, $col, $dx, $dy)';
}

/// 1つの図形オブジェクトを表すクラス
class DrawingObject {
  final String id;
  DrawingType type; // 変更可能にするため final を削除

  // 図形を構成する点群
  // - line/rectangle: [始点, 終点] の2点
  final List<AnchorPoint> points;

  // スタイル情報
  Color color;
  double strokeWidth;
  double markerHeight;
  int paddingX;
  double paddingY;
  LineStyle lineStyle;
  bool hasArrowStart;
  bool hasArrowEnd;
  bool isUpperRoute; // L字線のルート (true: 上/左優先, false: 下/右優先)
  String? filePath; // 画像ファイルのパス
  List<double> tableRowPositions; // テーブルの水平区切り線位置 (0.0-1.0)
  List<double> tableColPositions; // テーブルの垂直区切り線位置 (0.0-1.0)

  DrawingObject({
    required this.id,
    required this.type,
    required this.points,
    this.color = const Color(0xFFFF0000), // デフォルト赤
    this.strokeWidth = 2.0,
    this.markerHeight = 1.0,
    this.paddingX = 0,
    this.paddingY = 0.0,
    this.lineStyle = LineStyle.solid,
    this.hasArrowStart = false,
    this.hasArrowEnd = false,
    this.isUpperRoute = true,
    this.filePath,
    this.tableRowPositions = const [],
    this.tableColPositions = const [],
  });

  // コピー用 (Undo/Redo時のディープコピーに使用)
  DrawingObject copy() {
    return DrawingObject(
      id: id,
      type: type,
      points: points.map((p) => p.copyWith()).toList(),
      color: color,
      strokeWidth: strokeWidth,
      markerHeight: markerHeight,
      paddingX: paddingX,
      paddingY: paddingY,
      lineStyle: lineStyle,
      hasArrowStart: hasArrowStart,
      hasArrowEnd: hasArrowEnd,
      isUpperRoute: isUpperRoute,
      filePath: filePath,
      tableRowPositions: List.from(tableRowPositions),
      tableColPositions: List.from(tableColPositions),
    );
  }

  // 簡易的な矩形範囲取得（当たり判定用などに拡張可能）
  // Rect get bounds => ...

  // JSON変換
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.index, // enumはindexで保存
    'points': points.map((p) => p.toJson()).toList(),
    'color': color.value, // int値で保存
    'strokeWidth': strokeWidth,
    'markerHeight': markerHeight,
    'paddingX': paddingX,
    'paddingY': paddingY,
    'lineStyle': lineStyle.index,
    'hasArrowStart': hasArrowStart,
    'hasArrowEnd': hasArrowEnd,
    'isUpperRoute': isUpperRoute,
    'filePath': filePath,
    'tableRowPositions': tableRowPositions,
    'tableColPositions': tableColPositions,
  };

  factory DrawingObject.fromJson(Map<String, dynamic> json) {
    return DrawingObject(
      id: json['id'] as String,
      type: DrawingType.values[json['type'] as int],
      points: (json['points'] as List)
          .map((e) => AnchorPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      markerHeight: (json['markerHeight'] as num?)?.toDouble() ?? 1.0,
      paddingX: (json['paddingX'] as num?)?.toInt() ?? 0,
      paddingY: (json['paddingY'] as num?)?.toDouble() ?? 0.0,
      lineStyle: json['lineStyle'] != null
          ? LineStyle.values[json['lineStyle'] as int]
          : LineStyle.solid,
      hasArrowStart: json['hasArrowStart'] as bool? ?? false,
      hasArrowEnd: json['hasArrowEnd'] as bool? ?? false,
      isUpperRoute: json['isUpperRoute'] as bool? ?? true,
      filePath: json['filePath'] as String?,
      tableRowPositions: (json['tableRowPositions'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
      tableColPositions: (json['tableColPositions'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [],
    );
  }
}
