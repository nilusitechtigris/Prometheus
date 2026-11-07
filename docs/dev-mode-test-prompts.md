# Prompts for testing Dev mode

One well-designed prompt for testing what Dev mode's harness adds when a small model builds a web UI, then shorter ones and traps that a model working alone tends to fall into. They're also in the app: on the Compare page, press **Prompts** next to **Compare**.

## How to run a test

1. Pick the model and context window in Dev mode's top bar. For Qwen2.5 Coder 7B, use Q4_K_M on a 16 GB Mac or Q8_0 with 24 GB or more, and a **16K** context window. A smaller window can still work, but leaves little room for a page and its script together.
2. Open the Compare page (⧉ beside Send, or **Compare** in the top bar), paste a prompt and press **Compare**.
3. The app builds it twice in new folders: first with the harness off (one reply, saved as it came), then on. The model loads before either clock starts.
4. Both apps open side by side. Try them yourself, and read the scorecard under each.

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

One request, written to get a finished-looking web UI from a small model, and to test everything the harness does. Paste it into Compare as it is.

```text
Build a personal budget web app with a clean, modern dashboard look.

Layout: a header with the app's name and the current month. Under it, three summary cards side by side for Balance, Income and Spending, each with a big number. Below them, two columns: a card on the left with a form to add a transaction, and the list of transactions on the right.

Form: a description, an amount, a category (Food, Transport, Home, Fun or Other) and a choice of Income or Spending, with Spending chosen to start with, and an Add button. Don't add a transaction with an empty description or an amount of zero, and say why next to the field.

List: newest first. Each row shows the description, the category as a coloured badge, the date, and the amount in green for income or red for spending, with a delete button. Above the list, buttons show All, Income or Spending. When the list is empty, show a friendly message instead.

Behaviour: the cards and the list update straight away, and everything is still there after a reload.

Look: plenty of white space, rounded cards with soft shadows, one accent colour, clear labels on every field, and a layout that stacks into one column in a narrow window.
```

How it's written, and why:

- **The layout is spelled out top to bottom.** A small model follows a plan far better than it designs one, and a fixed layout gives both sides the same target.
- **Every name is given:** the cards, the categories, the buttons. Nothing is left for the model to invent, and you can check the result at a glance.
- **It asks for the parts that make a UI feel finished:** a default choice, checks on the form with a reason next to the field, colour that carries meaning, an empty state, and saving across a reload. These are where small models cut corners.
- **The look is described in words a model turns into classes:** cards, soft shadows, one accent colour and a layout that stacks. No library or framework is named, so neither side is pushed toward the internet.
- **Each part is something the scorecard can see:** fields to fill in, a form to send, a list that grows, totals that change, buttons to press.

Afterwards, open the harness-on side as a project and send the follow-ups below, to test changes across its files.

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
