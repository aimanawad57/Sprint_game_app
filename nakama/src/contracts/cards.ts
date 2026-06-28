enum CardColor {
  Red = "red",
  Orange = "orange",
  Yellow = "yellow",
  Green = "green",
  Blue = "blue",
  Purple = "purple"
}

enum CardShape {
  Star = "star",
  Diamond = "diamond",
  Heart = "heart",
  Spiral = "spiral",
  Circle = "circle",
  Sun = "sun"
}

type Card = {
  card_id: string;
  color: CardColor;
  shape: CardShape;
  count: number;
};
