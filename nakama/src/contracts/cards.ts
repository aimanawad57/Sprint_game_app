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
  Tree = "tree",
  House = "house",
  Circle = "circle",
  Flag = "flag"
}

type Card = {
  card_id: string;
  color: CardColor;
  shape: CardShape;
  count: number;
};
