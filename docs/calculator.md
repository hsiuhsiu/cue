# Instant calculator / 即時計算

## English

Type an expression directly in Cue's main
launcher to see its answer.
There is no separate calculator page or setting.

### Calculate and copy

1. Invoke Cue with **Option+Space** and type an expression, such as **`1+2*3`**.
2. A complete supported expression shows its answer as the first result.
   Matching apps and commands remain below it, within Cue's nine-result limit.
3. Press **Return** while the answer is selected, or **Command+1**, to copy only
   the answer and close Cue. Paste it with **Command+V** in the destination app.

Calculating does not read or change the clipboard; copying requires an explicit
action. Cue does not paste automatically. Continue typing to revise the
expression, use the arrow keys to choose another result, or press **Esc** to
close Cue. Input-method composition does not execute the copy action.

### Supported expressions

Use decimal numbers, **`+`**, **`-`**, **`*`**, **`/`**, **`^`** for powers, and parentheses.
Two adjacent asterisks, **`**`**, also mean a power: `2**10` is the same as `2^10`.
The equivalent symbols **`×`**, **`÷`**, and **`−`** are also accepted.
Powers run before unary signs, multiplication/division, and addition/subtraction;
parentheses change that order. Chained powers run from right to left: `2^3^2`
means `2^(3^2)`, giving `512`; `(2^3)^2` gives `64`. A negative base needs
parentheses: `(-2)^2` gives `4`, while `(-2^2)` gives `-4`.
Positive and negative signs are allowed within an expression,
such as `2*-3`. Numbers use ASCII digits and a **`.`** decimal point, regardless
of Cue's interface language. Scientific literals such as `1e-7` are supported.

| Expression | Answer |
| --- | --- |
| `1+2*3` | `7` |
| `(12+8)/4` | `5` |
| `12-20` | `-8` |
| `7/2` | `3.5` |
| `0.1+0.2` | `0.3` |
| `1e-7+0` | `1e-7` |
| `1/3` | `≈ 0.3333333333333333` |
| `2^10` | `1024` |
| `2^-3` | `0.125` |
| `2^3^2` | `512` |
| `9^0.5` | `≈ 3` |

After leading whitespace, an expression must start with a digit **0–9** or
**`(`**, and it must contain an arithmetic operator. A plain number does not
create a calculator result, so numeric app names can still be searched normally.
A sign in a scientific exponent alone does not count as an arithmetic operator:
`1e-7` stays a normal search, while `1e-7+0` calculates. Start a negative value
inside parentheses, for example **`(-2)+5`**, and use **`0.5`** rather than `.5`
at the beginning of the query.

The answer is prefixed with **`=`** when exact or **`≈`** when approximate. Exact
answers retain their digits; approximate answers use up to 16 significant digits.
Magnitudes below `0.000001` or at least `1e21` use compact scientific notation.
Copying omits the prefix and copies the displayed numeric value only. Input
numbers accept up to 38 significant digits, excluding leading/trailing zeros.

Integer powers use decimal arithmetic, including negative exponents such as
`2^-3`. Fractional powers use an approximate calculation and always show **`≈`**,
even when the displayed answer is a whole number. They accept positive bases;
zero to a positive power also produces zero. Every exponent must be between
`-10000` and `10000`, inclusive. `0^0`, zero to a negative power, and negative
bases with fractional exponents do not produce an answer. A fractional-power
input is rejected if preparing it for the approximate calculation would lose its
significant digits. Values outside the supported numeric range, including
intermediate overflow or underflow, also do not produce an answer.

Incomplete or unsupported expressions, division by zero, and values outside the
supported range do not show a calculator result. The parser accepts at most
512 UTF-8 bytes, 256 numbers/operator characters/parentheses, and a shared limit of
32 nested parentheses, powers, and unary signs, keeping work bounded while
typing. Grouping separators, `%`, functions, variables, and implicit
multiplication such as `2(3+4)` are not supported. Unit and currency conversion
remain separate future features.

### Search and privacy

A valid answer counts as a local result, so Cue does not add an automatic Google
fallback for that expression. **Command+Return** can still explicitly search the
current text in the default browser; **Command+K** shows browser choices. If an
expression is incomplete or unsupported, ordinary app, command, and Google
fallback behavior continues. Merely typing never sends the expression anywhere.

Calculation is entirely local and works with Cue networking and browser search
both disabled. Expressions and calculator results are not saved in Cue's
search-learning history. If Clipboard History recording is enabled, an answer
you explicitly copy follows its normal recording rules. macOS Universal
Clipboard and other clipboard managers follow their own settings.

## 正體中文

直接在 Cue 主搜尋輸入算式，
即可看到答案，不需要進入另一個計算機頁面，也沒有額外設定。

### 計算與拷貝

1. 按 **Option+Space** 叫出 Cue，輸入算式，例如 **`1+2*3`**。
2. 完整且支援的算式會把答案顯示在第一列；符合的 App 與指令仍列在下方，
   所有結果合計最多九列。
3. 選取答案時按 **Return**，或直接按 **Command+1**，只拷貝答案並收起 Cue，
   再到目標 App 按 **Command+V** 貼上。

單純計算不會讀取或修改剪貼簿，只有明確執行拷貝才會寫入，也不會自動貼上。
可以繼續打字修改算式、用方向鍵選擇其他結果，或按 **Esc** 收起 Cue。
輸入法仍在組字時不會執行拷貝。

### 支援的算式

支援十進位數字、**`+`**、**`-`**、**`*`**、**`/`**、次方 **`^`** 與括號。
兩個相鄰的星號 **`**`** 也表示次方：`2**10` 和 `2^10` 相同。也接受 **`×`**、
**`÷`**、**`−`**。先算次方，再套用正負號、乘除、最後加減，可用括號改變順序。
連續次方由右向左計算：`2^3^2` 等於 `2^(3^2)`，答案為 `512`；`(2^3)^2` 則為 `64`。
負數底數要加括號：`(-2)^2` 為 `4`，`(-2^2)` 則為 `-4`。算式內可使用正負號，
例如 `2*-3`。不論 Cue 介面語言為何，數字皆使用半形 0–9 與 **`.`** 小數點，
也支援 `1e-7` 這類科學記號。

| 算式 | 答案 |
| --- | --- |
| `1+2*3` | `7` |
| `(12+8)/4` | `5` |
| `12-20` | `-8` |
| `7/2` | `3.5` |
| `0.1+0.2` | `0.3` |
| `1e-7+0` | `1e-7` |
| `1/3` | `≈ 0.3333333333333333` |
| `2^10` | `1024` |
| `2^-3` | `0.125` |
| `2^3^2` | `512` |
| `9^0.5` | `≈ 3` |

忽略前方空白後，算式必須以 **0–9** 數字或 **`(`** 開頭，並含有運算符號。
單純數字不會產生計算結果，仍可正常搜尋以數字命名的 App。科學記號指數中的
正負號不算運算符號：`1e-7` 仍是一般搜尋，`1e-7+0` 才會計算。若要以負數
起始，可把它放在括號內，例如 **`(-2)+5`**；以小數起始時請用 **`0.5`**，
而非 `.5`。

精確答案前方顯示 **`=`** 並保留所有數位，近似值顯示 **`≈`**，
最多保留 16 位有效數字。絕對值小於 `0.000001` 或至少為 `1e21` 時，使用簡短
的科學記號。拷貝時只包含畫面上的數值，不包含前方符號。輸入數值最多接受
38 位有效數字，不計前方與尾端的零。

整數次方使用十進位運算，也支援 `2^-3` 這類負指數。小數次方使用近似運算，
即使顯示的答案恰好是整數，也一律標示 **`≈`**。小數次方接受正數底數；零的
正數次方也會得到零。所有指數都必須介於 `-10000` 與 `10000` 之間，包含兩端。
`0^0`、零的負數次方，以及負底數的小數次方不會產生答案。小數次方的輸入若在
轉成近似運算所需格式時會丟失有效數字，就不會進行計算。超出可處理範圍的數值，
包含中間運算的溢位或下溢，也不會產生答案。

尚未完成、不支援、除以零或超出可處理範圍的算式，不會顯示計算結果。
解析最多接受 512 個 UTF-8 位元組、256 個數值／運算符號字元／括號；
括號、次方與正負號共用 32 層巢狀深度上限，讓打字時的工作量維持有限。
不支援千分位分隔符、`%`、函數、變數或 `2(3+4)` 這類省略乘號的寫法；
單位與幣值換算仍屬於之後的獨立功能。

### 搜尋與隱私

有效答案算是本機結果，因此不會再為該算式自動加入 Google 備用搜尋。
仍可按 **Command+Return**，明確使用預設瀏覽器搜尋目前文字，或按
**Command+K** 顯示瀏覽器選擇。若算式不完整或不支援，原本的 App、指令及
Google 備用搜尋邏輯仍照常運作。單純打字不會把算式傳出去。

計算完全在本機進行，Cue 自行連網與瀏覽器搜尋都關閉時也能使用。算式及結果
不會存入 Cue 的搜尋學習記錄。若已啟用剪貼簿記錄，明確拷貝的答案會依一般
規則收錄；macOS 通用剪貼簿及其他剪貼簿管理程式仍依各自設定運作。
