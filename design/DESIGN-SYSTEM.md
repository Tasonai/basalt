# Vorssaint Design System (DS-2026)

Единая дизайн-система macOS-приложения **Vorssaint**.

## 1. Философия и визуальная иерархия

- **Тон продукта**: сфокусированный системный кокпит без маркетингового шума, лишних логотипов внутри редакторов и монохромной усталости.
- **Главный символ бренда**: живой маскот (`NotchMascotView`, `NotchMascotRig`, `CommandBarDroplet`) — единственный антропоморфный герой интерфейса, связывающий Dynamic Island, Command Bar и Onboarding.
- **Пять уровней поверхностей (`SurfaceTier`)**:
  1. `canvas` — фон рабочего поля редактора или окна настроек.
  2. `card` — групповые карточки `SettingsCard` с чёткой граничной иерархией.
  3. `elevated` — всплывающие инспекторы, Action Panel (`⌘K`), HUD-бары.
  4. `glass` — HUD, меню-поповер и плавающие пилюли на полупрозрачном стекле.
  5. `island` — глубокая обсидиановая поверхность Dynamic Island (`#000000` + hairline-блик).

## 2. Ювелирная категориальная палитра (`SemanticCategoryPalette`)

Вместо однотонного системного `Color.accentColor` во всех рядах и группах каждая функциональная область имеет семантический акцент (адаптированный под Light, Dark и `accessibilityContrast == .high`):

| Категория | `FeatureGroup` | Light / Dark / High-Contrast тональность |
| --- | --- | --- |
| Окна и док | `.windowsDock` | Sapphire / Sky Blue |
| Мышь и клавиатура | `.mouseKeyboard` | Indigo / Iris |
| Буфер и файлы | `.clipboardFiles` | Teal / Cyan |
| Звук и аудиомикшер | `.sound` | Coral / Crimson |
| Энергия и экраны | `.energyDisplay` | Amber / Warm Gold |
| Быстрые инструменты | `.tools` | Emerald / Jade |
| Dynamic Island | `.dynamicIsland` | Violet / Amethyst |
| Мониторинг системы | `.monitor` | Mint / Emerald |

## 3. Типографика и метрики

- **Цифры в движении**: всегда `.monospacedDigit()` (таймеры, FPS, разрешения `W × H px`, проценты зума, уровни dB, телеметрия).
- **Концентрические скругления (`DesignRadius`)**: внешний радиус = внутренний радиус + отступ (`cardOuter = 14`, `cardInner = 10`, `tile = 7`, `pill = 8`).
- **Hairline-блик (`hairlineSpecularBorder`)**: 0.5–1pt верхний/периферийный градиентный блик для тёмных и стеклянных поверхностей без визуальной тяжести.

## 4. Кинетика (`DesignMotion`) и доступность

- Единый набор пружин:
  - `snappy` (отклик пилюль, кнопок, выбора пресетов).
  - `smooth` (переходы панелей и предпросмотров).
  - `gentle` (раскрытие секций и плавное появление).
- Любая кастомная анимация и progressive `NotchScrollEdgeFade` уважают `@Environment(\.accessibilityReduceMotion)`.

## 5. Runtime Metal Shaders (`VorssaintMetalShaders`)

- Компиляция шейдеров выполняется во время работы через `MTLCreateSystemDefaultDevice()?.makeLibrary(source:options:)` (без зависимости от CLI `metallib` на машине сборки) с потокобезопасным одноразовым кэшем.
- Ядро **`ditherGradient`**: треугольный дизеринг (triangular TPDF noise ±1 LSB в linear/sRGB) для полного устранения 8-битного бандинга градиентных фонов скриншотов и записей.
- Ядро **`directionalMotionBlur`**: направленное сглаживание движения камеры/курсора для ключевых кадров увеличения в редакторе записи.
- При отсутствии Metal-устройства (headless/CI) автоматически работает точный CoreGraphics / CoreImage fallback.
