# food

**What should I eat?** A small, dependency-free web app that picks a meal for you.

## Features
- Filter by cuisine, budget ($–$$$), time, and tags (vegetarian, vegan, spicy, healthy, comfort)
- Live match count; the button disables when nothing matches
- Avoids repeating any of your last 3 picks
- Favorites and recent picks, saved in your browser (`localStorage`)
- Filters remembered between visits
- Dark mode, mobile layout, keyboard support (press <kbd>Space</kbd> to pick)

## Run
Open `index.html` in a browser. No build step.

## Add a dish
Append an entry to `dishes.js`:
```js
{ id: "fish-tacos", name: "Fish Tacos", emoji: "🌮", cuisine: "Mexican", price: 2, time: 20, tags: ["healthy"] }
```
`id` must be unique and stable — favorites are stored by id.
