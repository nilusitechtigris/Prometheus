# Prompts for testing Dev mode

One well-designed prompt for testing what Dev mode's harness adds when a small model builds a web UI, a calmer one, a harder one with four pages, then shorter ones and traps that a model working alone tends to fall into. They're also in the app: on the Compare page, press **Prompts** next to **Compare**.

## How to run a test

1. Pick the model and context window in Dev mode's top bar. For Qwen2.5 Coder 7B, use Q4_K_M on a 16 GB Mac or Q8_0 with 24 GB or more, and a **16K** context window. A smaller window can still work, but leaves little room for a page and its script together.
2. Open the Compare page (⧉ beside Send, or **Compare** in the top bar), paste a prompt and press **Compare**.
3. The app builds it twice in new folders: first with the harness off (one reply, saved as it came), then on. The model loads before either clock starts.
4. Both apps open side by side. Try them yourself, and read the scorecard under each.
5. To look closer, press the arrow beside a side's score: that app fills the window, and **Off / On** at the top flips to the other one at the same size. **Fit** zooms a long app out until all of it shows. The camera button saves one picture of both apps at full length, with nothing cut off, in the comparison's folder, and copies it.

Both sides get the same facts: the code runs offline, a page opens in a browser with no internet, and Python has no display. The only difference is the harness.

A small model gives a different answer each time, so run a prompt two or three times before you trust a difference. Compare keeps every run under **Earlier**.

## The scorecard

| Line | What code checked |
| --- | --- |
| Shows something | The page isn't blank and doesn't show raw template tags such as `{{ name }}`, which only a server fills in |
| Opens without errors | No JavaScript error, crash or freeze while it loads and while it's used |
| Styled | Some style sheet applies, rather than the browser's plain default look |
| Works offline | It asks the internet for nothing, since nothing from there can load |
| Works when used | Code filled in every field, sent every form and pressed the buttons, and something on the page changed |
| Fits the window | Nothing is wider than the window |

## The prompt

One request, written to get a lively, finished-looking web UI from a small model, with colour and animation, and to test everything the harness does. Paste it into Compare as it is.

```text
Build a smoothie bar ordering web app called Juicy, with a bright, colourful look and lively animations.

Layout: a header with a colourful gradient, the app's name, and a cart button showing how many drinks are in the cart. Under it, filter buttons for All, Fruity, Green and Protein, and a Surprise me button. Below them, two columns: a grid of drink cards on the left, and the cart with the order form on the right.

Drinks: six cards, each in its own colour: Mango Sunrise (orange, Fruity, $5.50), Berry Blast (purple, Fruity, $6.00), Tropical Kiss (pink, Fruity, $6.50), Green Machine (green, Green, $6.00), Matcha Glow (teal, Green, $6.50) and Peanut Power (brown, Protein, $7.00). Each card shows a big emoji, the name, a one-line description, the price, a choice of Small, Medium or Large with Medium chosen to start with (Small is $1 less, Large $1 more), and an Add button. Surprise me picks a random drink, highlights its card and adds it to the cart.

Cart: each line shows the drink in its colour, its size, the quantity with minus and plus buttons, the line price and a remove button. Below the lines, show the subtotal, 10% off once the subtotal reaches $20, and the total. When the cart is empty, show a friendly message instead.

Order form: a name field, a pickup time (As soon as possible, In 15 minutes or In 30 minutes) and a Place order button. Don't place an order with an empty cart or an empty name, and say why next to the field. Placing an order empties the cart, shows a thank-you message with an order number, and adds the order to a Recent orders list, newest first.

Behaviour: the filters, the cart and the totals update straight away, and the cart and the recent orders are still there after a reload.

Motion: cards rise and fade into place when the page opens and when the filter changes; a card lifts with a deeper shadow on hover; the cart count pops when a drink is added; the total counts up to its new value; the highlighted card pulses; and a placed order sets off a burst of confetti in a fixed layer that covers the window, hides anything outside it and is removed when the burst ends. Keep each animation under a second, and only fade when the system asks for reduced motion.

Look: rounded cards with soft shadows, each drink's colour on its card and its cart line, white text on strong colours, one font, clear labels on every field, and a layout that stacks into one column in a narrow window.
```

How it's written, and why:

- **It's built like the budget dashboard below, with more to get right:** prices that follow rules (the size changes the price, 10% off from $20), a random action, and a second list that the first one feeds.
- **Colour carries meaning.** Each drink keeps its colour from its card to its cart line, which shows at a glance whether the markup, the styles and the script agree on names across files.
- **Every animation is named, with when it happens and how long it takes.** That gets CSS transitions and keyframes from a model, rather than a reach for an animation library from the internet, which the page can't load.
- **The motion stays inside the window.** Cards rise into place instead of sliding in from the side, and the confetti lives in a fixed layer that hides anything outside the window and goes away when it ends. Otherwise a page fails **Fits the window** in the middle of an animation, or keeps hundreds of confetti pieces.
- **It asks for reduced motion to be respected,** which is easy to leave out and quick to check in System Settings › Accessibility › Display.
- **Each part is still something the scorecard can see:** filters, size choices, fields, a form, quantity buttons, totals that change, and two lists that grow.

Afterwards, open the harness-on side as a project and send the follow-ups below, to test changes across its files.

## The budget dashboard

The main prompt before the smoothie bar: calmer, with one accent colour and no animation. Earlier comparisons used it, so run it again to compare with them.

```text
Build a personal budget web app with a clean, modern dashboard look.

Layout: a header with the app's name and the current month. Under it, three summary cards side by side for Balance, Income and Spending, each with a big number. Below them, two columns: a card on the left with a form to add a transaction, and the list of transactions on the right.

Form: a description, an amount, a category (Food, Transport, Home, Fun or Other) and a choice of Income or Spending, with Spending chosen to start with, and an Add button. Don't add a transaction with an empty description or an amount of zero, and say why next to the field.

List: newest first. Each row shows the description, the category as a coloured badge, the date, and the amount in green for income or red for spending, with a delete button. Above the list, buttons show All, Income or Spending. When the list is empty, show a friendly message instead.

Behaviour: the cards and the list update straight away, and everything is still there after a reload.

Look: plenty of white space, rounded cards with soft shadows, one accent colour, clear labels on every field, and a layout that stacks into one column in a narrow window.
```

How it's written, and why (the smoothie bar builds on the same ideas):

- **The layout is spelled out top to bottom.** A small model follows a plan far better than it designs one, and a fixed layout gives both sides the same target.
- **Every name is given:** the cards, the categories, the buttons. Nothing is left for the model to invent, and you can check the result at a glance.
- **It asks for the parts that make a UI feel finished:** a default choice, checks on the form with a reason next to the field, colour that carries meaning, an empty state, and saving across a reload. These are where small models cut corners.
- **The look is described in words a model turns into classes:** cards, soft shadows, one accent colour and a layout that stacks. No library or framework is named, so neither side is pushed toward the internet.
- **Each part is something the scorecard can see:** fields to fill in, a form to send, a list that grows, totals that change, buttons to press.

## The festival: four pages

The hardest prompt here: four pages in one app, saved acts and tickets that show up on other pages, two themes and more motion. It's new, and no runs of it are recorded yet.

It is too large for the agent the app uses by default. That agent writes each file in one reply of at most 4,096 tokens and asks for a page under 90 lines, whatever the context window is, and this app's script alone is likely to need more. So run it with **v3, the roomy build**, whose sizes follow the context window: in the lab edition, choose **v3** on the Harness switch above the agent, and a **32K** context window. With v3 chosen, the harness-off side gets the same room for its one reply, so the comparison is a fair one. Expect it to take much longer than the smoothie bar on each side.

```text
Build a web app for a two-day music festival called Aurora Nights, with a dark, glowing look, bold colour and smooth animation. It has four pages: Home, Lineup, My schedule and Tickets. The pages are parts of one page: only one shows at a time, and moving between them loads nothing.

Navigation: a bar stays at the top with the festival's name, a link to each page, a count of saved acts on My schedule's link, a count of tickets on Tickets' link, and a button that switches between a dark and a light theme, dark to start with. A link shows its page, is marked as the current one, and puts the page's name at the end of the address: #home, #lineup, #schedule or #tickets. Opening or reloading the app with one of those in the address shows that page, and the browser's Back button returns to the page before.

Home: a tall hero with the festival's name in big gradient text, the dates 12 to 13 July, one line about the festival, and a countdown to the next 12 July in days, hours, minutes and seconds that ticks every second. Two buttons, See the lineup and Get tickets, go to those pages. Under the hero, three cards with big numbers: 8 acts, 3 stages and 8 hours of music.

Lineup: eight act cards, and each stage has its own colour: Sun stage is amber, Moon stage is violet and River stage is teal. Saturday: Neon Harbour (synth pop, Sun stage, 18:00), Velvet Static (dream rock, Moon stage, 18:30), Paper Comets (indie folk, River stage, 20:00) and The Night Kites (electro, Sun stage, 21:30). Sunday: Amber Echo (soul, River stage, 17:00), Silver Tide (ambient, Moon stage, 18:00), Midnight Arcade (disco, Sun stage, 19:30) and Low Sun Choir (folk, Moon stage, 20:00). Every set lasts one hour. Each card shows a big emoji, the name, the genre, the stage as a badge in its colour, the day and time, and a heart button that saves the act to My schedule or takes it out again, filled while it is saved. Above the cards, buttons show All, Saturday or Sunday, and a search box filters by name as I type. When nothing matches, say so.

My schedule: the saved acts under a Saturday heading and a Sunday heading, earliest first. Each row shows its stage's colour, the time from start to end, the name, the stage and a remove button. When two saved acts on the same day overlap, both rows show a Clash badge. With nothing saved, show a friendly message and a button to the lineup.

Tickets: three ticket cards: Day pass at $89, Weekend pass at $149 and VIP weekend at $289, each with one line about it and minus and plus buttons for a quantity from 0 to 6. Beside them, an order summary: a line for each kind of ticket chosen, the subtotal, a booking fee of $5 for each ticket, a promo code field with an Apply button, and the total. The code AURORA10 takes 10% off the subtotal, and any other code says it isn't valid. Under the summary, a name field, an email field and a Buy tickets button. Don't buy with no tickets, an empty name or an email without an @ sign, and say why next to the field. Buying sets the quantities back to zero, shows a confirmation with a booking number, and adds the booking to a Your bookings list on the page, newest first, with its tickets and total.

Behaviour: the counts in the bar, the schedule and the totals update straight away. The saved acts, the ticket quantities, the bookings and the theme are still there after a reload.

Motion: a page fades in and rises a little when it opens, in 300 milliseconds. The mark under the current link slides to the new one. The cards on a page rise and fade into place one after another, when the page opens and when the filter changes. A card lifts and glows in its stage's colour on hover. The heart pops when an act is saved, and a count in the bar pops when it changes. Home's three numbers count up from zero, and the total counts to its new value. The confirmation flips into view. The gradient in the hero's title drifts slowly and is the only motion that loops; everything else takes under a second. Nothing slides in from outside the window, and when the system asks for reduced motion, only fade and keep the gradient still.

Look: a near-black background with large, soft glows of amber, violet and teal behind the content. Cards like frosted glass: a little see-through, with a thin light border and soft shadows. Rounded corners, big bold headings, white text on dark, one font, each stage's colour on its badge, its card's glow and its schedule row, and clear labels on every field. The light theme keeps the same colours on a pale background. In a narrow window everything stacks into one column and the bar's links stay in reach.
```

How it's written, and why:

- **Four pages, one file.** The prompt says what a page is here: a part of one page, shown one at a time, with its name at the end of the address so that a reload and the Back button work. A model working alone tends to link to files it never writes, or to reach for a router from the internet.
- **What you do on one page shows on another.** A heart on Lineup changes My schedule and a count in the bar, and a ticket changes another count. That shows whether the script keeps its data in one place and draws every page from it.
- **The rules can be checked by using the app:** two pairs of acts that clash and one pair that only touches, a fee for each ticket, a promo code, and three reasons a purchase is refused.
- **Colour carries meaning in three places.** A stage keeps its colour from the act's card to its glow and its schedule row.
- **Every animation is named, with when it happens.** One of them loops and is called out as the only one, so a page that never stops moving is easy to spot. Nothing slides in from outside the window, which would fail **Fits the window** in the middle of a move.
- **The look is described in words a model turns into CSS:** glows, frosted glass, gradient text, two themes. No library, font or icon set is named.

What to check by hand, on each side:

- Open Tickets, reload, and it's still Tickets. Back returns to the page before.
- Save Neon Harbour and Velvet Static: both rows show Clash. Amber Echo and Silver Tide don't, because one ends as the other starts.
- Two Weekend passes: subtotal $298, booking fee $10, and with AURORA10 $29.80 off, for a total of $278.20.
- After a reload the saved acts, the quantities, the bookings and the theme are as they were.

## More to try

Shorter prompts, each a few minutes per side, and each testing a different part of an app.

**Habit tracker:** a list with a checkbox on each row.

```text
Make a habit tracker web app. I type a habit and add it, and each habit shows as a row with a checkbox for today, a streak count and a delete button. Show how many habits are done today at the top.
```

**Tip calculator:** numbers that update as you type.

```text
Make a tip calculator web app with the bill amount, a tip of 10, 15 or 20 percent or a custom percent, and the number of people. Show the tip, the total and what each person pays, updating as I type.
```

**Quiz:** a page that moves through steps.

```text
Make a quiz web app with five multiple choice questions about space. Show one question at a time with four answer buttons, tell me whether I was right, and show my score at the end with a button to play again.
```

**Recipe box:** cards, and a search that filters them.

```text
Make a recipe box web app. A form takes a recipe's name, its ingredients and the minutes it takes. Show the recipes as cards, and add a search box that filters them by name as I type.
```

**Pomodoro timer:** a clock that runs by itself.

```text
Make a pomodoro timer web app with a 25 minute work timer and a 5 minute break, big digits, start, pause and reset buttons, and a count of the work sessions finished today.
```

**Kanban board:** things that move between columns.

```text
Make a kanban board web app with To do, Doing and Done columns. I add a card to To do, and each card has buttons to move it left or right and to delete it. Show how many cards each column has.
```

## Traps

A model working alone tends to fail these in the same few ways. Watch for them on the harness-off side.

**A chart:** it reaches for a chart library from the internet, which can't load here.

```text
Make a sales dashboard web app that shows these monthly sales as a bar chart: Jan 120, Feb 95, Mar 140, Apr 180, May 160, Jun 210. Add cards for the total, the best month and the monthly average.
```

**A server:** it writes a Flask, PHP or Node back end, whose page shows raw template tags with no server to fill them in. Qwen3 4B did this for a habit tracker on the first real comparison.

```text
Make a guestbook web app where visitors leave their name and a message, and everyone's messages show newest first.
```

**Icons and fonts:** it links Font Awesome, Google Fonts and Bootstrap from the internet, so the page loses its look and its icons.

```text
Make a landing page for a coffee shop called Ember Roast, with a menu and prices, the opening hours, a contact form that thanks the visitor, and an icon for each section.
```

## Follow-ups: changing an app across its files

These test changes to an app that's already there, which touch its page, styles and script together. After a Compare, press **Open as Project** on one side. Set **Harness On or Off** to match that side, then send these one at a time in the agent's box. Do the same on the other side.

For the budget app from the prompt above:

```text
Add a dark mode switch to the header, and remember it after a reload.
```

```text
Show the spending for each category as a row of coloured bars under the totals.
```

```text
Ask before deleting a transaction.
```

## Writing down results

To keep runs comparable, note the Mac, model, quantization and context window. Compare's header shows all of them.

| Prompt | Model, context | Harness off | Harness on | Notes |
| --- | --- | --- | --- | --- |
| Budget | Qwen2.5 Coder 7B Q8_0, 16K | ?/6, time | ?/6, time | |

For numbers you can publish, the measuring run grades twelve web app tasks the same way, and adds a stricter check: an app that keeps a list has to show what was typed into it. The tasks are in [scripts/dev_tasks.py](../scripts/dev_tasks.py).
