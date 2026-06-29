const CARD_CATALOG: ReadonlyArray<Card> = [
  {card_id: "card_001", color: CardColor.Red, shape: CardShape.Star, count: 1},
  {card_id: "card_002", color: CardColor.Red, shape: CardShape.Diamond, count: 2},
  {card_id: "card_003", color: CardColor.Red, shape: CardShape.Heart, count: 3},
  {card_id: "card_004", color: CardColor.Red, shape: CardShape.Spiral, count: 4},
  {card_id: "card_005", color: CardColor.Red, shape: CardShape.Circle, count: 5},
  {card_id: "card_006", color: CardColor.Red, shape: CardShape.Sun, count: 6},
  {card_id: "card_007", color: CardColor.Orange, shape: CardShape.Star, count: 2},
  {card_id: "card_008", color: CardColor.Orange, shape: CardShape.Diamond, count: 3},
  {card_id: "card_009", color: CardColor.Orange, shape: CardShape.Heart, count: 4},
  {card_id: "card_010", color: CardColor.Orange, shape: CardShape.Spiral, count: 5},
  {card_id: "card_011", color: CardColor.Orange, shape: CardShape.Circle, count: 6},
  {card_id: "card_012", color: CardColor.Orange, shape: CardShape.Sun, count: 1},
  {card_id: "card_013", color: CardColor.Yellow, shape: CardShape.Star, count: 3},
  {card_id: "card_014", color: CardColor.Yellow, shape: CardShape.Diamond, count: 4},
  {card_id: "card_015", color: CardColor.Yellow, shape: CardShape.Heart, count: 5},
  {card_id: "card_016", color: CardColor.Yellow, shape: CardShape.Spiral, count: 6},
  {card_id: "card_017", color: CardColor.Yellow, shape: CardShape.Circle, count: 1},
  {card_id: "card_018", color: CardColor.Yellow, shape: CardShape.Sun, count: 2},
  {card_id: "card_019", color: CardColor.Green, shape: CardShape.Star, count: 4},
  {card_id: "card_020", color: CardColor.Green, shape: CardShape.Diamond, count: 5},
  {card_id: "card_021", color: CardColor.Green, shape: CardShape.Heart, count: 6},
  {card_id: "card_022", color: CardColor.Green, shape: CardShape.Spiral, count: 1},
  {card_id: "card_023", color: CardColor.Green, shape: CardShape.Circle, count: 2},
  {card_id: "card_024", color: CardColor.Green, shape: CardShape.Sun, count: 3},
  {card_id: "card_025", color: CardColor.Blue, shape: CardShape.Star, count: 5},
  {card_id: "card_026", color: CardColor.Blue, shape: CardShape.Diamond, count: 6},
  {card_id: "card_027", color: CardColor.Blue, shape: CardShape.Heart, count: 1},
  {card_id: "card_028", color: CardColor.Blue, shape: CardShape.Spiral, count: 2},
  {card_id: "card_029", color: CardColor.Blue, shape: CardShape.Circle, count: 3},
  {card_id: "card_030", color: CardColor.Blue, shape: CardShape.Sun, count: 4},
  {card_id: "card_031", color: CardColor.Purple, shape: CardShape.Star, count: 6},
  {card_id: "card_032", color: CardColor.Purple, shape: CardShape.Diamond, count: 1},
  {card_id: "card_033", color: CardColor.Purple, shape: CardShape.Heart, count: 2},
  {card_id: "card_034", color: CardColor.Purple, shape: CardShape.Spiral, count: 3},
  {card_id: "card_035", color: CardColor.Purple, shape: CardShape.Circle, count: 4},
  {card_id: "card_036", color: CardColor.Purple, shape: CardShape.Sun, count: 5},
  {card_id: "card_037", color: CardColor.Red, shape: CardShape.Diamond, count: 3},
  {card_id: "card_038", color: CardColor.Red, shape: CardShape.Heart, count: 4},
  {card_id: "card_039", color: CardColor.Red, shape: CardShape.Spiral, count: 5},
  {card_id: "card_040", color: CardColor.Red, shape: CardShape.Circle, count: 6},
  {card_id: "card_041", color: CardColor.Orange, shape: CardShape.Star, count: 3},
  {card_id: "card_042", color: CardColor.Orange, shape: CardShape.Heart, count: 5},
  {card_id: "card_043", color: CardColor.Orange, shape: CardShape.Spiral, count: 6},
  {card_id: "card_044", color: CardColor.Orange, shape: CardShape.Circle, count: 1},
  {card_id: "card_045", color: CardColor.Orange, shape: CardShape.Sun, count: 2},
  {card_id: "card_046", color: CardColor.Yellow, shape: CardShape.Star, count: 4},
  {card_id: "card_047", color: CardColor.Yellow, shape: CardShape.Diamond, count: 5},
  {card_id: "card_048", color: CardColor.Yellow, shape: CardShape.Heart, count: 6},
  {card_id: "card_049", color: CardColor.Yellow, shape: CardShape.Circle, count: 2},
  {card_id: "card_050", color: CardColor.Green, shape: CardShape.Heart, count: 1},
  {card_id: "card_051", color: CardColor.Green, shape: CardShape.Spiral, count: 2},
  {card_id: "card_052", color: CardColor.Green, shape: CardShape.Circle, count: 3},
  {card_id: "card_053", color: CardColor.Green, shape: CardShape.Sun, count: 4},
  {card_id: "card_054", color: CardColor.Blue, shape: CardShape.Star, count: 6},
  {card_id: "card_055", color: CardColor.Blue, shape: CardShape.Diamond, count: 1},
  {card_id: "card_056", color: CardColor.Blue, shape: CardShape.Spiral, count: 3},
  {card_id: "card_057", color: CardColor.Blue, shape: CardShape.Circle, count: 4},
  {card_id: "card_058", color: CardColor.Blue, shape: CardShape.Sun, count: 5},
  {card_id: "card_059", color: CardColor.Purple, shape: CardShape.Star, count: 1},
  {card_id: "card_060", color: CardColor.Purple, shape: CardShape.Diamond, count: 2},
  {card_id: "card_061", color: CardColor.Purple, shape: CardShape.Heart, count: 3},
  {card_id: "card_062", color: CardColor.Purple, shape: CardShape.Sun, count: 6}
];

const CARD_CATALOG_SIZE = 62;

function validateCardCatalog(catalog: ReadonlyArray<Card>): void {
  if (catalog.length !== CARD_CATALOG_SIZE) {
    throw new Error(
      "Invalid card catalog: expected " +
        CARD_CATALOG_SIZE +
        " cards but found " +
        catalog.length +
        "."
    );
  }

  const allowedColors = [
    CardColor.Red,
    CardColor.Orange,
    CardColor.Yellow,
    CardColor.Green,
    CardColor.Blue,
    CardColor.Purple
  ];
  const allowedShapes = [
    CardShape.Star,
    CardShape.Diamond,
    CardShape.Heart,
    CardShape.Spiral,
    CardShape.Circle,
    CardShape.Sun
  ];
  const seenIds: {[cardId: string]: boolean} = {};

  catalog.forEach((card, index) => {
    const expectedId = "card_" + ("000" + (index + 1).toString()).slice(-3);
    if (card.card_id !== expectedId) {
      throw new Error(
        "Invalid card catalog: expected ID " +
          expectedId +
          " at row " +
          (index + 1) +
          "."
      );
    }
    if (seenIds[card.card_id]) {
      throw new Error("Invalid card catalog: duplicate ID " + card.card_id + ".");
    }
    if (allowedColors.indexOf(card.color) === -1) {
      throw new Error("Invalid card catalog: invalid color for " + card.card_id + ".");
    }
    if (allowedShapes.indexOf(card.shape) === -1) {
      throw new Error("Invalid card catalog: invalid shape for " + card.card_id + ".");
    }
    if (!Number.isInteger(card.count) || card.count < 1 || card.count > 6) {
      throw new Error("Invalid card catalog: invalid count for " + card.card_id + ".");
    }

    seenIds[card.card_id] = true;
  });
}
