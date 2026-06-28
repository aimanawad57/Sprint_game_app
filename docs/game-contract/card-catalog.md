# Card Catalog Contract

## Card shape

Every physical card is represented by one catalog row:

```typescript
type Card = {
  card_id: string;
  color: CardColor;
  shape: CardShape;
  count: number;
};
```

## Allowed values

Colors:

```text
red
orange
yellow
green
blue
purple
```

Shapes:

```text
star
diamond
heart
spiral
circle
sun
```

Counts:

```text
1, 2, 3, 4, 5, 6
```

The words shape, symbol, and texture refer to the same card attribute. The
contract uses `shape` consistently in data.

## Validation rules

The completed catalog must satisfy all of these checks:

1. It contains exactly 62 rows excluding the header.
2. Every `card_id` matches `card_001` through `card_062`.
3. Every `card_id` is unique.
4. Every color belongs to the allowed color list.
5. Every shape belongs to the allowed shape list.
6. Every count is an integer from 1 through 6.
7. No attribute is blank.
8. Duplicate combinations are permitted only when confirmed against the
   physical deck.

The catalog order has no gameplay meaning. The server copies and shuffles the
catalog for every match.
