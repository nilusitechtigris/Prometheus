"""Writes the coding tasks Dev mode's agent is measured on, as JSON. Each has hidden checks the agent never sees.

Run a debug build with LOCALAI_DEV_TASKS set to the file this writes, and LOCALAI_DEV_OUT to where the report goes.
Usage: python3 scripts/dev_tasks.py tasks.json
"""
import json
import sys

RUN = """
import io, runpy, sys, contextlib

def run(path, argv=(), lines=()):
    out = io.StringIO()
    feed = iter(lines)
    def fake_input(prompt=""):
        out.write(str(prompt))
        try:
            return next(feed)
        except StopIteration:
            raise EOFError
    saved_argv, saved_input = sys.argv, __builtins__.input if hasattr(__builtins__, "input") else __builtins__["input"]
    sys.argv = [path] + list(argv)
    import builtins
    builtins.input = fake_input
    try:
        with contextlib.redirect_stdout(out):
            try:
                runpy.run_path(path, run_name="__main__")
            except SystemExit as e:
                if e.code not in (None, 0):
                    raise
    finally:
        sys.argv = saved_argv
        builtins.input = saved_input
    return out.getvalue()
"""

LONG = "import json\n\n\n"
for i in range(1, 61):
    LONG += f"def rule_{i}(value):\n    \"\"\"Applies rule {i}.\"\"\"\n    total = value + {i}\n    if total > {i * 3}:\n        return total - 1\n    return total\n\n\n"
LONG += "def apply_all(value):\n    return rule_1(rule_2(rule_3(value)))\n\n\nif __name__ == \"__main__\":\n    print(apply_all(1))\n"

TASKS = [
    {
        "id": "fizzbuzz",
        "target": "fizzbuzz.py",
        "steps": ["Write fizzbuzz.py that prints the numbers 1 to 30, one per line, with Fizz for multiples of 3, Buzz for multiples of 5 and FizzBuzz for both."],
        "check": RUN + """
lines = run("fizzbuzz.py").split()
assert len(lines) == 30, lines
assert lines[0] == "1" and lines[2] == "Fizz" and lines[4] == "Buzz" and lines[14] == "FizzBuzz" and lines[29] == "FizzBuzz", lines
""",
    },
    {
        "id": "primes",
        "target": "primes.py",
        "steps": ["Create primes.py with a function primes_up_to(n) that returns a list of the prime numbers up to and including n."],
        "check": """
from primes import primes_up_to
assert primes_up_to(30) == [2, 3, 5, 7, 11, 13, 17, 19, 23, 29]
assert primes_up_to(2) == [2]
assert primes_up_to(1) == []
assert primes_up_to(0) == []
""",
    },
    {
        "id": "word_count",
        "target": "count.py",
        "files": {"text.txt": "the cat and the dog and the bird\nThe end of the story and a cat\n"},
        "steps": ["Write a script count.py that reads text.txt and prints the 3 most common words, ignoring case, one per line as: word count"],
        "check": RUN + """
lines = [l.strip() for l in run("count.py").strip().splitlines()]
assert lines == ["the 5", "and 3", "cat 2"], lines
""",
    },
    {
        "id": "csv_report",
        "target": "report.py",
        "files": {"sales.csv": "region,item,price,quantity\nnorth,pen,2.50,4\nsouth,book,10.00,2\nnorth,bag,20.00,1\neast,pen,2.50,10\nsouth,pen,2.50,2\n"},
        "steps": ["Write report.py that reads sales.csv and prints the total revenue (price times quantity) for each region, sorted by region name, one per line as: region: total"],
        "check": RUN + """
import re
lines = [l.strip() for l in run("report.py").strip().splitlines() if l.strip()]
got = [(m.group(1), float(m.group(2))) for m in (re.match(r"(\\w+):\\s*\\$?([\\d.]+)", l) for l in lines) if m]
assert got == [("east", 25.0), ("north", 30.0), ("south", 25.0)], lines
""",
    },
    {
        "id": "stack_class",
        "target": "stack.py",
        "steps": ["Create stack.py with a class Stack that has push(item), pop(), peek(), is_empty() and __len__. pop() and peek() on an empty stack must raise IndexError."],
        "check": """
from stack import Stack
s = Stack()
assert s.is_empty() and len(s) == 0
s.push(1); s.push(2)
assert s.peek() == 2 and len(s) == 2
assert s.pop() == 2 and s.pop() == 1
for name in ("pop", "peek"):
    try:
        getattr(s, name)()
    except IndexError:
        pass
    else:
        raise SystemExit(name + " should raise")
""",
    },
    {
        "id": "todo_cli",
        "target": "todo.py",
        "steps": ["Write todo.py, a command line todo list saved in todos.json. Commands: 'python todo.py add some text', 'python todo.py list' which prints each item with its number starting at 1, and 'python todo.py done N' which removes item N."],
        "check": RUN + """
import os
if os.path.exists("todos.json"):
    os.remove("todos.json")
run("todo.py", ["add", "buy", "milk"])
run("todo.py", ["add", "walk"])
listed = run("todo.py", ["list"])
assert "buy milk" in listed and "walk" in listed and "1" in listed, listed
run("todo.py", ["done", "1"])
listed = run("todo.py", ["list"])
assert "buy milk" not in listed and "walk" in listed, listed
""",
    },
    {
        "id": "guess_game",
        "target": "guess.py",
        "steps": ["Write guess.py, a number guessing game. It picks a secret from 1 to 100 with random, then keeps asking for a guess with input(), printing 'Too low', 'Too high', or 'Correct' and stopping when it's right."],
        "check": RUN + """
import random
random.seed(1)
real = random.randint
random.randint = lambda a, b: 50
random.randrange = lambda *a: 50
random.choice = lambda s: 50
out = run("guess.py", lines=["10", "90", "50"])
assert "low" in out.lower() and "high" in out.lower() and "correct" in out.lower(), out
""",
    },
    {
        "id": "two_files",
        "target": "app.py",
        "steps": ["Create shapes.py with functions circle_area(r) and square_area(s), and app.py which imports them and prints circle_area(2) and then square_area(3), one per line."],
        "check": RUN + """
import math, shapes
assert abs(shapes.circle_area(2) - math.pi * 4) < 0.01
assert shapes.square_area(3) == 9
lines = run("app.py").split()
assert abs(float(lines[0]) - math.pi * 4) < 0.01 and float(lines[1]) == 9, lines
""",
    },
    {
        "id": "add_function",
        "target": "calc.py",
        "files": {"calc.py": "def add(a, b):\n    return a + b\n\n\ndef subtract(a, b):\n    return a - b\n\n\ndef main():\n    print(add(2, 3))\n    print(subtract(5, 1))\n\n\nif __name__ == \"__main__\":\n    main()\n"},
        "open": "calc.py",
        "steps": ["Add a function power(a, b) and make main also print power(2, 10)."],
        "check": RUN + """
import calc
assert calc.power(2, 3) == 8 and calc.add(1, 1) == 2 and calc.subtract(3, 1) == 2
lines = run("calc.py").split()
assert lines == ["5", "4", "1024"], lines
""",
    },
    {
        "id": "empty_list",
        "target": "stats.py",
        "files": {"stats.py": "def average(numbers):\n    return sum(numbers) / len(numbers)\n\n\ndef largest(numbers):\n    return max(numbers)\n\n\nif __name__ == \"__main__\":\n    print(average([1, 2, 3]))\n    print(largest([1, 2, 3]))\n"},
        "open": "stats.py",
        "steps": ["average([]) crashes. Make it return 0 for an empty list, and make largest([]) return None."],
        "check": """
import stats
assert stats.average([]) == 0 and stats.largest([]) is None
assert stats.average([2, 4]) == 3 and stats.largest([1, 5]) == 5
""",
    },
    {
        "id": "crash_type",
        "target": "invoice.py",
        "files": {"invoice.py": "items = [(\"pen\", 2), (\"book\", 10), (\"bag\", 25)]\n\n\ndef total(entries):\n    result = 0\n    for name, price in entries:\n        result += price\n    return result\n\n\ndef line(name, price):\n    return name + \": \" + price\n\n\ndef main():\n    for name, price in items:\n        print(line(name, price))\n    print(\"Total: \" + total(items))\n\n\nif __name__ == \"__main__\":\n    main()\n"},
        "fix": ["invoice.py"],
        "steps": ["Fix this."],
        "check": RUN + """
out = run("invoice.py")
assert "pen: 2" in out and "bag: 25" in out and "Total: 37" in out, out
""",
    },
    {
        "id": "crash_key",
        "target": "scores.py",
        "files": {"scores.py": "import json\n\n\ndef load():\n    return json.loads('[{\"name\": \"Ann\", \"score\": 3}, {\"name\": \"Bo\"}, {\"name\": \"Cy\", \"score\": 8}]')\n\n\ndef best(rows):\n    return max(rows, key=lambda row: row[\"score\"])\n\n\ndef main():\n    rows = load()\n    print(best(rows)[\"name\"])\n\n\nif __name__ == \"__main__\":\n    main()\n"},
        "fix": ["scores.py"],
        "steps": ["Fix this."],
        "check": RUN + """
assert "Cy" in run("scores.py")
""",
    },
    {
        "id": "endless_loop",
        "target": "countdown.py",
        "files": {"countdown.py": "def countdown(n):\n    while n != 0:\n        print(n)\n        n = n - 2\n    print(\"done\")\n\n\nif __name__ == \"__main__\":\n    countdown(5)\n"},
        "open": "countdown.py",
        "steps": ["countdown(5) never ends. Fix it so it counts 5, 3, 1 and then prints done."],
        "check": RUN + """
lines = run("countdown.py").split()
assert lines == ["5", "3", "1", "done"], lines
""",
    },
    {
        "id": "add_tests",
        "target": "test_text_utils.py",
        "files": {"text_utils.py": "def slug(text):\n    return \"-\".join(text.lower().split())\n\n\ndef initials(name):\n    return \"\".join(word[0].upper() for word in name.split())\n"},
        "open": "text_utils.py",
        "steps": ["Add tests for this file."],
        "check": """
import unittest, test_text_utils
suite = unittest.defaultTestLoader.loadTestsFromModule(test_text_utils)
assert suite.countTestCases() >= 2, suite.countTestCases()
result = unittest.TextTestRunner(verbosity=0).run(suite)
assert result.wasSuccessful()
""",
    },
    {
        "id": "long_file",
        "target": "rules.py",
        "files": {"rules.py": LONG},
        "open": "rules.py",
        "steps": ["Change rule_37 so it returns the total doubled instead of total - 1 when the total is over the limit."],
        "check": """
import rules
assert rules.rule_37(200) == 474
assert rules.rule_37(1) == 38
assert rules.rule_60(1) == 61 and rules.rule_1(9) == 9 and rules.apply_all(1) == 6
source = open("rules.py").read()
assert source.count("def rule_") == 60
""",
    },
    {
        "id": "follow_up",
        "target": "greet.py",
        "steps": ["Write greet.py that prints Hello, World!", "Now make it take a name from the command line, and use World if none is given."],
        "check": RUN + """
assert "Hello, World!" in run("greet.py")
assert "Hello, Ann!" in run("greet.py", ["Ann"])
""",
    },
]


THREE = """import json


def load(text):
    return json.loads(text)


def names(rows):
    return [row["name"].upper() for row in rows]


def total(rows):
    result = 0
    for row in rows:
        result += row["price"] * row["qty"]
    return result


def summary(rows):
    return "Items: " + len(rows) + ", total: " + str(total(rows))


def main():
    rows = load('[{"name": "pen", "price": 2, "qty": "3"}, {"name": "ink", "price": 5, "qty": "1"}]')
    print(", ".join(names(rows)))
    print(summary(rows))
    print(average(rows))


if __name__ == "__main__":
    main()
"""

TASKS += [
    {
        "id": "three_bugs",
        "target": "orders.py",
        "files": {"orders.py": THREE},
        "fix": ["orders.py"],
        "steps": ["Fix this."],
        "note": "Each crash hides the next: qty is text, len isn't text, and average doesn't exist yet.",
        "check": RUN + """
import orders, re
out = run("orders.py")
assert "PEN, INK" in out and "Items: 2" in out and "total: 11" in out, out
""",
    },
    {
        "id": "json_nested",
        "target": "staff.py",
        "files": {"staff.json": '{"teams": [{"name": "core", "people": [{"name": "Ann", "age": 30}, {"name": "Bo", "age": 40}]}, {"name": "ops", "people": [{"name": "Cy", "age": 25}]}]}\n'},
        "steps": ["Write staff.py that reads staff.json and prints each team's name and the average age of its people, one team per line as: name average"],
        "check": RUN + """
lines = [l.split() for l in run("staff.py").strip().splitlines()]
assert [l[0].strip(":") for l in lines] == ["core", "ops"] and float(lines[0][1]) == 35 and float(lines[1][1]) == 25, lines
""",
    },
    {
        "id": "class_method",
        "target": "bank.py",
        "files": {"bank.py": "class Account:\n    def __init__(self, owner, balance=0):\n        self.owner = owner\n        self.balance = balance\n\n    def deposit(self, amount):\n        if amount <= 0:\n            raise ValueError(\"amount must be positive\")\n        self.balance += amount\n\n    def report(self):\n        return f\"{self.owner}: {self.balance}\"\n\n\ndef main():\n    account = Account(\"Ann\", 100)\n    account.deposit(50)\n    print(account.report())\n\n\nif __name__ == \"__main__\":\n    main()\n"},
        "open": "bank.py",
        "steps": ["Add a withdraw(amount) method that raises ValueError if the amount is more than the balance or not positive, and a transfer(other, amount) method that moves money to another account."],
        "check": """
from bank import Account
a, b = Account("A", 100), Account("B")
a.withdraw(30)
assert a.balance == 70
a.transfer(b, 20)
assert a.balance == 50 and b.balance == 20
for bad in (-1, 0, 1000):
    try:
        a.withdraw(bad)
    except ValueError:
        pass
    else:
        raise SystemExit("withdraw should refuse %s" % bad)
a.deposit(1)
assert a.report() == "A: 51"
""",
    },
    {
        "id": "wrong_order",
        "target": "ranking.py",
        "files": {"ranking.py": "players = [(\"Ann\", 12), (\"Bo\", 30), (\"Cy\", 7), (\"Di\", 21)]\n\n\ndef top(rows, count):\n    ordered = sorted(rows, key=lambda row: row[1])\n    return ordered[:count]\n\n\nif __name__ == \"__main__\":\n    for name, score in top(players, 2):\n        print(name, score)\n"},
        "open": "ranking.py",
        "steps": ["top() should give the highest scores, but it's giving the lowest. Fix it."],
        "check": """
import ranking
assert ranking.top(ranking.players, 2) == [("Bo", 30), ("Di", 21)]
""",
    },
    {
        "id": "text_stats",
        "target": "textstats.py",
        "steps": ["Write textstats.py with a function analyze(text) that returns a dictionary with the keys words, sentences and longest. words is the number of words, sentences counts endings in . ! or ?, and longest is the longest word without punctuation."],
        "check": """
from textstats import analyze
r = analyze("Hello there, world! How are you today?")
assert r["words"] == 7 and r["sentences"] == 2 and r["longest"] in ("Hello", "there", "world", "today"), r
""",
    },
    {
        "id": "rename",
        "target": "convert.py",
        "files": {"convert.py": "def c_to_f(c):\n    return c * 9 / 5 + 32\n\n\ndef f_to_c(f):\n    return (f - 32) * 5 / 9\n\n\ndef table(low, high):\n    for c in range(low, high + 1, 10):\n        print(c, c_to_f(c))\n\n\nif __name__ == \"__main__\":\n    table(0, 30)\n    print(f_to_c(212))\n"},
        "open": "convert.py",
        "steps": ["Rename c_to_f to celsius_to_fahrenheit everywhere."],
        "check": """
import convert
assert convert.celsius_to_fahrenheit(100) == 212 and not hasattr(convert, "c_to_f") and convert.f_to_c(32) == 0
""",
    },
    {
        "id": "matrix",
        "target": "matrix.py",
        "steps": ["Create matrix.py with functions transpose(m) and multiply(a, b) for matrices stored as lists of lists. multiply must raise ValueError if the sizes don't fit."],
        "check": """
from matrix import transpose, multiply
assert transpose([[1, 2, 3], [4, 5, 6]]) == [[1, 4], [2, 5], [3, 6]]
assert multiply([[1, 2], [3, 4]], [[5, 6], [7, 8]]) == [[19, 22], [43, 50]]
try:
    multiply([[1, 2]], [[1, 2]])
except ValueError:
    pass
else:
    raise SystemExit("should refuse")
""",
    },
    {
        "id": "dedupe_keep_order",
        "target": "contacts.py",
        "files": {"contacts.csv": "name,email\nAnn,ann@x.org\nBo,BO@x.org\nann b,ann@X.org\nCy,cy@x.org\nBob,bo@x.org\n"},
        "steps": ["Write contacts.py that reads contacts.csv, removes rows with a repeated email (ignoring case) keeping the first, and writes the rest to clean.csv with the same header. It should also print how many rows it removed."],
        "check": RUN + """
import csv
out = run("contacts.py")
rows = list(csv.DictReader(open("clean.csv")))
assert [r["name"] for r in rows] == ["Ann", "Bo", "Cy"], rows
assert "2" in out, out
""",
    },
]

GAME = RUN + """
import builtins, re
source = open("main.py").read()
assert not re.search(r"\\b(pygame|tkinter|turtle)\\b", source), "uses a display"
asked = []
real_run = run

def play(lines):
    out = io.StringIO()
    feed = iter(lines)
    def fake_input(prompt=""):
        asked.append(prompt)
        out.write(str(prompt) + "\\n")
        try:
            return next(feed)
        except StopIteration:
            raise EOFError
    saved = builtins.input
    builtins.input = fake_input
    try:
        with contextlib.redirect_stdout(out):
            try:
                runpy.run_path("main.py", run_name="__main__")
            except (EOFError, SystemExit):
                pass
    finally:
        builtins.input = saved
    return out.getvalue()

text = play(["1", "2", "shoot", "left", "right", "fire", "y", "1", "2", "3"])
assert len(asked) >= 2, "only asked %d times" % len(asked)
assert len(text.strip()) > 40, text
"""

TASKS += [
    {
        "id": "text_game",
        "target": "main.py",
        "steps": ["write me a simple game a pov shoting game in python"],
        "check": GAME,
    },
    {
        "id": "text_game_two",
        "target": "adventure.py",
        "steps": ["Create adventure.py, a small game where you explore a dungeon and fight monsters."],
        "check": GAME.replace("main.py", "adventure.py"),
    },
]

SALES = "item,sold\\nPens,120\\nBooks,75\\nBags,40\\nCups,95\\n"

TASKS += [
    {"id": "pov_shooter", "target": "index.html", "page": "index.html", "game": True, "steps": ["write me a simple game a pov shoting game..."]},
    {"id": "pong", "target": "index.html", "page": "index.html", "game": True, "steps": ["Make a pong game where I play against the computer."]},
    {"id": "snake", "target": "index.html", "page": "index.html", "game": True, "steps": ["Make a snake game."]},
    {"id": "breakout", "target": "index.html", "page": "index.html", "game": True, "steps": ["Build a breakout game."]},
    {"id": "clicker", "target": "index.html", "page": "index.html", "game": True, "steps": ["Make a cookie clicker game."]},
    {"id": "memory_cards", "target": "index.html", "page": "index.html", "game": True, "steps": ["Make a memory card matching game."]},
    {"id": "paint", "target": "index.html", "page": "index.html", "game": False, "steps": ["Make a drawing app with a canvas where I draw with the mouse."]},
    {"id": "bar_chart", "target": "index.html", "page": "index.html", "game": False, "files": {"sales.csv": SALES}, "steps": ["Draw a bar chart of sales.csv as a web page."]},
    {"id": "bakery", "target": "index.html", "page": "index.html", "game": False, "steps": ["Make a web page for my bakery with a menu and opening hours."]},
    {"id": "calculator", "target": "index.html", "page": "index.html", "game": False, "steps": ["Make a calculator web page with buttons."]},
]

json.dump(TASKS, open(sys.argv[1], "w"), indent=1)
print(len(TASKS), "tasks")
