// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized copy introduced across the Vorssaint overhaul, covering all 15
/// supported app languages with zero em-dashes and full LocalizationTests parity.
struct OverhaulStrings {
    // Epic 0: Editors & Visual Settings Previews
    let resetZoomHelp: String
    let previewInteractiveHint: String
    let switcherPreviewLayoutLabel: String
    let scrollPreviewCurveLabel: String
    let snapPreviewTitle: String
    let marginLabel: String

    // Epic 1: Mascot Onboarding & Role Workspaces
    let mascotCustomizeTitle: String
    let workspaceMinimalistName: String
    let workspaceMinimalistDesc: String
    let workspaceCreatorName: String
    let workspaceCreatorDesc: String
    let workspaceDeveloperName: String
    let workspaceDeveloperDesc: String
    let workspaceFullPowerName: String
    let workspaceFullPowerDesc: String
    let sandboxTitle: String
    let sandboxSubtitle: String
    let sandboxTryPet: String
    let sandboxTryPalette: String
    let sandboxTrySnap: String
    let extrasGroupTitle: String
    let extrasGroupCaption: String

    // Epic 2: Dynamic Island 2.0, OTP, Focus Mode & Mascot Reactions
    let copyOTPButton: String
    let otpCopiedBadge: String
    let focusModeTitle: String
    let focusModeCaption: String
    let smartOrderTitle: String
    let smartOrderCaption: String
    let momentAIReady: String
    let momentCountdown: String
    let momentCodeCopied: String
    let momentSweep: String

    static func localized(_ language: AppLanguage) -> OverhaulStrings {
        switch language {
        case .enUS:
            return OverhaulStrings(
                resetZoomHelp: "Reset zoom to fit",
                previewInteractiveHint: "Click a zone to preview",
                switcherPreviewLayoutLabel: "Live layout preview",
                scrollPreviewCurveLabel: "Response curve",
                snapPreviewTitle: "Edge & corner zones",
                marginLabel: "Margin",
                mascotCustomizeTitle: "Customize your companion",
                workspaceMinimalistName: "Minimalist",
                workspaceMinimalistDesc: "Island controls, clipboard, and clean energy.",
                workspaceCreatorName: "Creator",
                workspaceCreatorDesc: "Screen studio, screenshot pro, shelf, and audio mixer.",
                workspaceDeveloperName: "Developer",
                workspaceDeveloperDesc: "Command bar, ports, brew, AI agents, and tiling.",
                workspaceFullPowerName: "Full Power",
                workspaceFullPowerDesc: "Every system tool, cleaner, display, and HUD ready.",
                sandboxTitle: "Interactive sandbox",
                sandboxSubtitle: "Click or pet your companion before you begin.",
                sandboxTryPet: "Pet mascot",
                sandboxTryPalette: "Switch tint",
                sandboxTrySnap: "Test celebration",
                extrasGroupTitle: "Extras & Automations",
                extrasGroupCaption: "Optional messaging download cleanup and background organizers.",
                copyOTPButton: "Copy code",
                otpCopiedBadge: "Code copied",
                focusModeTitle: "Respect macOS Focus",
                focusModeCaption: "Hold subtle visits and mirrors quiet while Do Not Disturb or Focus is active.",
                smartOrderTitle: "Smart contextual priority",
                smartOrderCaption: "Keep media, calls, timers, and AI runs ahead of idle modules.",
                momentAIReady: "AI ready",
                momentCountdown: "Countdown beat",
                momentCodeCopied: "Code copied",
                momentSweep: "Sweep suggestion"
            )
        case .ru:
            return OverhaulStrings(
                resetZoomHelp: "Сбросить масштаб по окну",
                previewInteractiveHint: "Нажмите на зону для предпросмотра",
                switcherPreviewLayoutLabel: "Живой предпросмотр раскладки",
                scrollPreviewCurveLabel: "Кривая отклика",
                snapPreviewTitle: "Зоны краёв и углов",
                marginLabel: "Отступ",
                mascotCustomizeTitle: "Настройте маскота под себя",
                workspaceMinimalistName: "Минималист",
                workspaceMinimalistDesc: "Базовый Dynamic Island, буфер обмена и питание.",
                workspaceCreatorName: "Креатор",
                workspaceCreatorDesc: "Запись экрана, скриншоты Pro, полка файлов и аудиомикшер.",
                workspaceDeveloperName: "Разработчик",
                workspaceDeveloperDesc: "Command Bar, порты, Homebrew, ИИ-агенты и тайлинг.",
                workspaceFullPowerName: "Полная мощь",
                workspaceFullPowerDesc: "Все системные утилиты, очистка, дисплеи и HUD сразу.",
                sandboxTitle: "Интерактивная песочница",
                sandboxSubtitle: "Погладьте маскота или смените стиль перед запуском.",
                sandboxTryPet: "Погладить маскота",
                sandboxTryPalette: "Сменить цвет",
                sandboxTrySnap: "Отпраздновать",
                extrasGroupTitle: "Дополнения и автоматизация",
                extrasGroupCaption: "Необязательная очистка загрузок мессенджеров и фоновые правила.",
                copyOTPButton: "Копировать код",
                otpCopiedBadge: "Код скопирован",
                focusModeTitle: "Учитывать Фокусировку macOS",
                focusModeCaption: "Приглушать прогулки маскота и лишние баннеры при активном режиме Не беспокоить.",
                smartOrderTitle: "Умный приоритет модулей",
                smartOrderCaption: "Поднимать медиа, звонки, таймеры и ИИ-агентов перед прочими модулями.",
                momentAIReady: "ИИ готов",
                momentCountdown: "Обратный отсчёт",
                momentCodeCopied: "Код скопирован",
                momentSweep: "Уборка диска"
            )
        case .ptBR:
            return OverhaulStrings(
                resetZoomHelp: "Redefinir zoom para ajustar",
                previewInteractiveHint: "Clique em uma zona para visualizar",
                switcherPreviewLayoutLabel: "Visualização ao vivo",
                scrollPreviewCurveLabel: "Curva de resposta",
                snapPreviewTitle: "Zonas de borda e canto",
                marginLabel: "Margem",
                mascotCustomizeTitle: "Personalize seu mascote",
                workspaceMinimalistName: "Minimalista",
                workspaceMinimalistDesc: "Controles da ilha, área de transferência e energia.",
                workspaceCreatorName: "Criador",
                workspaceCreatorDesc: "Estúdio de tela, capturas pro, estante e mixer de áudio.",
                workspaceDeveloperName: "Desenvolvedor",
                workspaceDeveloperDesc: "Barra de comandos, portas, brew, agentes de IA e janelas.",
                workspaceFullPowerName: "Poder total",
                workspaceFullPowerDesc: "Todas as ferramentas do sistema, limpeza, telas e HUD.",
                sandboxTitle: "Arena interativa",
                sandboxSubtitle: "Faça carinho ou personalize o mascote antes de começar.",
                sandboxTryPet: "Fazer carinho",
                sandboxTryPalette: "Trocar cor",
                sandboxTrySnap: "Comemorar",
                extrasGroupTitle: "Extras e Automações",
                extrasGroupCaption: "Limpeza opcional de downloads de mensageiros e organizadores.",
                copyOTPButton: "Copiar código",
                otpCopiedBadge: "Código copiado",
                focusModeTitle: "Respeitar o Foco do macOS",
                focusModeCaption: "Mantém visitas e avisos discretos quando Não Perturbe está ativo.",
                smartOrderTitle: "Ordem contextual inteligente",
                smartOrderCaption: "Mantém mídia, chamadas, timers e IA à frente dos outros módulos.",
                momentAIReady: "IA pronta",
                momentCountdown: "Contagem regressiva",
                momentCodeCopied: "Código copiado",
                momentSweep: "Limpeza sugerida"
            )
        case .tr:
            return OverhaulStrings(
                resetZoomHelp: "Yakınlaştırmayı pencereye sığdır",
                previewInteractiveHint: "Önizlemek için bir alana tıklayın",
                switcherPreviewLayoutLabel: "Canlı düzen önizlemesi",
                scrollPreviewCurveLabel: "Tepki eğrisi",
                snapPreviewTitle: "Kenar ve köşe alanları",
                marginLabel: "Boşluk",
                mascotCustomizeTitle: "Maskotunuzu özelleştirin",
                workspaceMinimalistName: "Minimalist",
                workspaceMinimalistDesc: "Dinamik Ada denetimleri, pano ve temel enerji araçları.",
                workspaceCreatorName: "İçerik Üreticisi",
                workspaceCreatorDesc: "Ekran stüdyosu, gelişmiş yakalama, raf ve ses mikseri.",
                workspaceDeveloperName: "Geliştirici",
                workspaceDeveloperDesc: "Komut çubuğu, portlar, brew, yapay zeka ajanları ve döşeme.",
                workspaceFullPowerName: "Tam Güç",
                workspaceFullPowerDesc: "Tüm sistem araçları, temizlik, ekranlar ve HUD hazır.",
                sandboxTitle: "Etkileşimli deneme alanı",
                sandboxSubtitle: "Başlamadan önce maskotunuzu sevin veya stilini değiştirin.",
                sandboxTryPet: "Maskotu sev",
                sandboxTryPalette: "Rengi değiştir",
                sandboxTrySnap: "Kutla",
                extrasGroupTitle: "Ekstralar ve Otomasyonlar",
                extrasGroupCaption: "İsteğe bağlı mesajlaşma indirme temizliği ve düzenleyiciler.",
                copyOTPButton: "Kodu kopyala",
                otpCopiedBadge: "Kod kopyalandı",
                focusModeTitle: "macOS Odak moduna uy",
                focusModeCaption: "Rahatsız Etme açıkken maskot ziyaretlerini ve bannerları sessiz tutar.",
                smartOrderTitle: "Akıllı bağlam önceliği",
                smartOrderCaption: "Medya, çağrılar, zamanlayıcılar ve yapay zeka görevlerini öne alır.",
                momentAIReady: "Yapay zeka hazır",
                momentCountdown: "Geri sayım",
                momentCodeCopied: "Kod kopyalandı",
                momentSweep: "Temizlik önerisi"
            )
        case .es:
            return OverhaulStrings(
                resetZoomHelp: "Restablecer zoom para ajustar",
                previewInteractiveHint: "Haz clic en una zona para previsualizar",
                switcherPreviewLayoutLabel: "Vista previa en vivo",
                scrollPreviewCurveLabel: "Curva de respuesta",
                snapPreviewTitle: "Zonas de borde y esquina",
                marginLabel: "Margen",
                mascotCustomizeTitle: "Personaliza tu mascota",
                workspaceMinimalistName: "Minimalista",
                workspaceMinimalistDesc: "Controles de la isla, portapapeles y energía básica.",
                workspaceCreatorName: "Creador",
                workspaceCreatorDesc: "Estudio de pantalla, capturas pro, estante y mezclador.",
                workspaceDeveloperName: "Desarrollador",
                workspaceDeveloperDesc: "Barra de comandos, puertos, brew, agentes de IA y ventanas.",
                workspaceFullPowerName: "Potencia total",
                workspaceFullPowerDesc: "Todas las utilidades del sistema, limpiador, pantallas y HUD.",
                sandboxTitle: "Zona interactiva",
                sandboxSubtitle: "Acaricia o ajusta a tu mascota antes de empezar.",
                sandboxTryPet: "Acariciar",
                sandboxTryPalette: "Cambiar color",
                sandboxTrySnap: "Celebrar",
                extrasGroupTitle: "Extras y Automatizaciones",
                extrasGroupCaption: "Limpieza opcional de descargas de mensajería y organizadores.",
                copyOTPButton: "Copiar código",
                otpCopiedBadge: "Código copiado",
                focusModeTitle: "Respetar Concentración de macOS",
                focusModeCaption: "Silencia paseos y avisos secundarios cuando No Molestar está activo.",
                smartOrderTitle: "Prioridad contextual inteligente",
                smartOrderCaption: "Mantiene multimedia, llamadas, temporizadores e IA en primer plano.",
                momentAIReady: "IA lista",
                momentCountdown: "Cuenta atrás",
                momentCodeCopied: "Código copiado",
                momentSweep: "Limpieza sugerida"
            )
        case .sk:
            return OverhaulStrings(
                resetZoomHelp: "Prispôsobiť priblíženie oknu",
                previewInteractiveHint: "Kliknutím na zónu zobrazíte náhľad",
                switcherPreviewLayoutLabel: "Živý náhľad rozloženia",
                scrollPreviewCurveLabel: "Krivka odozvy",
                snapPreviewTitle: "Zóny okrajov a rohov",
                marginLabel: "Okraj",
                mascotCustomizeTitle: "Prispôsobte si maskota",
                workspaceMinimalistName: "Minimalista",
                workspaceMinimalistDesc: "Ovládanie ostrova, schránka a základná správa energie.",
                workspaceCreatorName: "Tvorca",
                workspaceCreatorDesc: "Štúdio záznamu obrazovky, snímky pro, polička a mixér zvuku.",
                workspaceDeveloperName: "Vývojár",
                workspaceDeveloperDesc: "Príkazový riadok, porty, brew, AI agenti a rozloženie okien.",
                workspaceFullPowerName: "Plný výkon",
                workspaceFullPowerDesc: "Všetky systémové nástroje, čistič, displeje a HUD.",
                sandboxTitle: "Interaktívne ihrisko",
                sandboxSubtitle: "Pred spustením maskota pohlaďte alebo upravte.",
                sandboxTryPet: "Pohladiť maskota",
                sandboxTryPalette: "Zmeniť farbu",
                sandboxTrySnap: "Osláviť",
                extrasGroupTitle: "Doplnky a automatizácia",
                extrasGroupCaption: "Voliteľné čistenie stiahnutých súborov z komunikátorov.",
                copyOTPButton: "Kopírovať kód",
                otpCopiedBadge: "Kód skopírovaný",
                focusModeTitle: "Rešpektovať režim Sústreďovania",
                focusModeCaption: "Počas režimu Nerušiť ponechá návštevy maskota a bannery tiché.",
                smartOrderTitle: "Inteligentná kontextová priorita",
                smartOrderCaption: "Drží médiá, hovory, časovače a AI pred nečinnými modulmi.",
                momentAIReady: "AI pripravená",
                momentCountdown: "Odpočítavanie",
                momentCodeCopied: "Kód skopírovaný",
                momentSweep: "Návrh čistenia"
            )
        case .de:
            return OverhaulStrings(
                resetZoomHelp: "Zoom an Fenster anpassen",
                previewInteractiveHint: "Bereich zur Vorschau anklicken",
                switcherPreviewLayoutLabel: "Live-Layout-Vorschau",
                scrollPreviewCurveLabel: "Reaktionskurve",
                snapPreviewTitle: "Rand- und Eckzonen",
                marginLabel: "Abstand",
                mascotCustomizeTitle: "Maskottchen anpassen",
                workspaceMinimalistName: "Minimalist",
                workspaceMinimalistDesc: "Island-Steuerung, Zwischenablage und Energieoptionen.",
                workspaceCreatorName: "Creator",
                workspaceCreatorDesc: "Bildschirmstudio, Screenshots Pro, Ablage und Audiomixer.",
                workspaceDeveloperName: "Entwickler",
                workspaceDeveloperDesc: "Befehlsleiste, Ports, Brew, KI-Agenten und Fensterkacheln.",
                workspaceFullPowerName: "Volle Kraft",
                workspaceFullPowerDesc: "Alle Systemwerkzeuge, Cleaner, Displays und HUD sofort aktiv.",
                sandboxTitle: "Interaktive Vorschau",
                sandboxSubtitle: "Streichle dein Maskottchen oder wechsle die Farbe vor dem Start.",
                sandboxTryPet: "Streicheln",
                sandboxTryPalette: "Farbe wechseln",
                sandboxTrySnap: "Jubeln",
                extrasGroupTitle: "Extras & Automationen",
                extrasGroupCaption: "Optionale Bereinigung von Messenger-Downloads im Hintergrund.",
                copyOTPButton: "Code kopieren",
                otpCopiedBadge: "Code kopiert",
                focusModeTitle: "macOS-Fokus beachten",
                focusModeCaption: "Hält Besuche und Meldungen bei aktivem Fokus ruhig.",
                smartOrderTitle: "Intelligente Kontextpriorität",
                smartOrderCaption: "Hält Medien, Anrufe, Timer und KI vor inaktiven Modulen.",
                momentAIReady: "KI bereit",
                momentCountdown: "Countdown",
                momentCodeCopied: "Code kopiert",
                momentSweep: "Bereinigung"
            )
        case .fr:
            return OverhaulStrings(
                resetZoomHelp: "Réinitialiser le zoom",
                previewInteractiveHint: "Cliquez sur une zone pour prévisualiser",
                switcherPreviewLayoutLabel: "Aperçu en direct",
                scrollPreviewCurveLabel: "Courbe de réponse",
                snapPreviewTitle: "Zones de bord et de coin",
                marginLabel: "Marge",
                mascotCustomizeTitle: "Personnalisez votre mascotte",
                workspaceMinimalistName: "Minimaliste",
                workspaceMinimalistDesc: "Contrôles de l’îlot, presse-papiers et énergie essentielle.",
                workspaceCreatorName: "Créateur",
                workspaceCreatorDesc: "Studio d’écran, captures pro, étagère et mixeur audio.",
                workspaceDeveloperName: "Développeur",
                workspaceDeveloperDesc: "Barre de commandes, ports, brew, agents IA et fenêtres.",
                workspaceFullPowerName: "Pleine puissance",
                workspaceFullPowerDesc: "Tous les outils système, nettoyeur, écrans et HUD.",
                sandboxTitle: "Bac à sable interactif",
                sandboxSubtitle: "Caressez ou stylisez votre mascotte avant de commencer.",
                sandboxTryPet: "Caresser",
                sandboxTryPalette: "Changer de teinte",
                sandboxTrySnap: "Célébrer",
                extrasGroupTitle: "Extras et Automatisations",
                extrasGroupCaption: "Nettoyage facultatif des téléchargements de messagerie.",
                copyOTPButton: "Copier le code",
                otpCopiedBadge: "Code copié",
                focusModeTitle: "Respecter Concentration macOS",
                focusModeCaption: "Garde les visites et bannières calmes en mode Ne pas déranger.",
                smartOrderTitle: "Priorité contextuelle intelligente",
                smartOrderCaption: "Place médias, appels, minuteurs et IA devant les modules inactifs.",
                momentAIReady: "IA prête",
                momentCountdown: "Compte à rebours",
                momentCodeCopied: "Code copié",
                momentSweep: "Nettoyage suggéré"
            )
        case .it:
            return OverhaulStrings(
                resetZoomHelp: "Ripristina zoom adatto",
                previewInteractiveHint: "Fai clic su una zona per l’anteprima",
                switcherPreviewLayoutLabel: "Anteprima layout dal vivo",
                scrollPreviewCurveLabel: "Curva di risposta",
                snapPreviewTitle: "Zone di bordo e angolo",
                marginLabel: "Margine",
                mascotCustomizeTitle: "Personalizza la tua mascotte",
                workspaceMinimalistName: "Minimalista",
                workspaceMinimalistDesc: "Controlli dell’isola, appunti ed energia essenziale.",
                workspaceCreatorName: "Creator",
                workspaceCreatorDesc: "Studio schermo, catture pro, mensola file e mixer audio.",
                workspaceDeveloperName: "Sviluppatore",
                workspaceDeveloperDesc: "Barra comandi, porte, brew, agenti IA e finestre.",
                workspaceFullPowerName: "Massima potenza",
                workspaceFullPowerDesc: "Tutti gli strumenti di sistema, pulizia, schermi e HUD.",
                sandboxTitle: "Area interattiva",
                sandboxSubtitle: "Accarezza o personalizza la mascotte prima di iniziare.",
                sandboxTryPet: "Accarezza",
                sandboxTryPalette: "Cambia colore",
                sandboxTrySnap: "Festeggia",
                extrasGroupTitle: "Extra e Automazioni",
                extrasGroupCaption: "Pulizia facoltativa dei download di messaggistica.",
                copyOTPButton: "Copia codice",
                otpCopiedBadge: "Codice copiato",
                focusModeTitle: "Rispetta Full Immersion",
                focusModeCaption: "Mantiene visite e avvisi discreti quando Non disturbare è attivo.",
                smartOrderTitle: "Priorità contestuale intelligente",
                smartOrderCaption: "Mantiene media, chiamate, timer e IA davanti ai moduli inattivi.",
                momentAIReady: "IA pronta",
                momentCountdown: "Conto alla rovescia",
                momentCodeCopied: "Codice copiato",
                momentSweep: "Pulizia suggerita"
            )
        case .ja:
            return OverhaulStrings(
                resetZoomHelp: "ウィンドウに合わせてリセット",
                previewInteractiveHint: "ゾーンをクリックしてプレビュー",
                switcherPreviewLayoutLabel: "リアルタイムレイアウト",
                scrollPreviewCurveLabel: "応答カーブ",
                snapPreviewTitle: "端と角のスナップ領域",
                marginLabel: "余白",
                mascotCustomizeTitle: "マスコットをカスタマイズ",
                workspaceMinimalistName: "ミニマリスト",
                workspaceMinimalistDesc: "Dynamic Island、クリップボード、省電力の基本セット。",
                workspaceCreatorName: "クリエイター",
                workspaceCreatorDesc: "画面収録スタジオ、高機能スクリーンショット、シェルフ、ミキサー。",
                workspaceDeveloperName: "開発者",
                workspaceDeveloperDesc: "コマンドバー、ポート管理、Homebrew、AIエージェント、ウィンドウ整列。",
                workspaceFullPowerName: "フルパワー",
                workspaceFullPowerDesc: "すべてのシステムツール、クリーナー、ディスプレイ管理を一括有効化。",
                sandboxTitle: "インタラクティブ体験",
                sandboxSubtitle: "始める前にマスコットをなでたり色を変えたりできます。",
                sandboxTryPet: "なでる",
                sandboxTryPalette: "色を変更",
                sandboxTrySnap: "お祝いアクション",
                extrasGroupTitle: "拡張機能と自動化",
                extrasGroupCaption: "メッセージアプリのダウンロード整理などオプションの自動化。",
                copyOTPButton: "コードをコピー",
                otpCopiedBadge: "コピーしました",
                focusModeTitle: "macOS集中モードに連動",
                focusModeCaption: "集中モード中はマスコットの移動や通知バナーを控えめにします。",
                smartOrderTitle: "スマートコンテキスト優先",
                smartOrderCaption: "再生中メディア、通話、タイマー、AI実行を優先表示します。",
                momentAIReady: "AI準備完了",
                momentCountdown: "カウントダウン",
                momentCodeCopied: "コードコピー",
                momentSweep: "クリーン提案"
            )
        case .ko:
            return OverhaulStrings(
                resetZoomHelp: "창 크기에 맞게 확대/축소 초기화",
                previewInteractiveHint: "영역을 클릭해 미리 보기",
                switcherPreviewLayoutLabel: "실시간 레이아웃 미리 보기",
                scrollPreviewCurveLabel: "응답 곡선",
                snapPreviewTitle: "가장자리 및 모서리 영역",
                marginLabel: "여백",
                mascotCustomizeTitle: "마스코트 꾸미기",
                workspaceMinimalistName: "미니멀리스트",
                workspaceMinimalistDesc: "다이나믹 아일랜드 제어, 클립보드, 기본 전원 도구.",
                workspaceCreatorName: "크리에이터",
                workspaceCreatorDesc: "화면 녹화 스튜디오, 프로 캡처, 파일 선반, 오디오 믹서.",
                workspaceDeveloperName: "개발자",
                workspaceDeveloperDesc: "커맨드 바, 포트 관리, Homebrew, AI 에이전트, 창 타일링.",
                workspaceFullPowerName: "풀 파워",
                workspaceFullPowerDesc: "모든 시스템 유틸리티, 클리너, 디스플레이, HUD 활성화.",
                sandboxTitle: "인터랙티브 샌드박스",
                sandboxSubtitle: "시작하기 전에 마스코트를 쓰다듬거나 색상을 바꿔 보세요.",
                sandboxTryPet: "쓰다듬기",
                sandboxTryPalette: "색상 바꾸기",
                sandboxTrySnap: "축하 반응",
                extrasGroupTitle: "추가 기능 및 자동화",
                extrasGroupCaption: "메신저 다운로드 정리 및 백그라운드 자동화 옵션.",
                copyOTPButton: "코드 복사",
                otpCopiedBadge: "코드 복사됨",
                focusModeTitle: "macOS 집중 모드 존중",
                focusModeCaption: "방해 금지나 집중 모드가 켜져 있으면 마스코트 방문을 조용히 유지합니다.",
                smartOrderTitle: "스마트 상황 우선순위",
                smartOrderCaption: "미디어, 통화, 타이머, AI 실행을 대기 모듈보다 먼저 표시합니다.",
                momentAIReady: "AI 준비 완료",
                momentCountdown: "카운트다운",
                momentCodeCopied: "코드 복사됨",
                momentSweep: "정리 제안"
            )
        case .uk:
            return OverhaulStrings(
                resetZoomHelp: "Скинути масштаб за вікном",
                previewInteractiveHint: "Натисніть на зону для перегляду",
                switcherPreviewLayoutLabel: "Живий перегляд макета",
                scrollPreviewCurveLabel: "Крива відгуку",
                snapPreviewTitle: "Зони країв і кутів",
                marginLabel: "Відступ",
                mascotCustomizeTitle: "Налаштуйте маскота під себе",
                workspaceMinimalistName: "Мінімаліст",
                workspaceMinimalistDesc: "Керування островом, буфер обміну та базове живлення.",
                workspaceCreatorName: "Креатор",
                workspaceCreatorDesc: "Студія запису екрана, знімки Pro, полиця файлів і мікшер.",
                workspaceDeveloperName: "Розробник",
                workspaceDeveloperDesc: "Панель команд, порти, brew, ШІ-агенти й розміщення вікон.",
                workspaceFullPowerName: "Повна потужність",
                workspaceFullPowerDesc: "Усі системні утиліти, очищувач, дисплеї та HUD одразу.",
                sandboxTitle: "Інтерактивна пісочниця",
                sandboxSubtitle: "Погладьте маскота або змініть його вигляд перед початком.",
                sandboxTryPet: "Погладити",
                sandboxTryPalette: "Змінити колір",
                sandboxTrySnap: "Відсвяткувати",
                extrasGroupTitle: "Додатково та автоматизація",
                extrasGroupCaption: "Необов’язкове очищення завантажень месенджерів.",
                copyOTPButton: "Скопіювати код",
                otpCopiedBadge: "Код скопійовано",
                focusModeTitle: "Поважати Зосередження macOS",
                focusModeCaption: "Стримує візити маскота й зайві сповіщення в режимі Не турбувати.",
                smartOrderTitle: "Розумний контекстний пріоритет",
                smartOrderCaption: "Піднімає медіа, дзвінки, таймери та ШІ перед неактивними модулями.",
                momentAIReady: "ШІ готовий",
                momentCountdown: "Зворотний відлік",
                momentCodeCopied: "Код скопійовано",
                momentSweep: "Прибирання диска"
            )
        case .zhHans:
            return OverhaulStrings(
                resetZoomHelp: "重置为适合窗口大小",
                previewInteractiveHint: "点击区域以预览",
                switcherPreviewLayoutLabel: "实时布局预览",
                scrollPreviewCurveLabel: "响应曲线",
                snapPreviewTitle: "边缘与角落吸附区",
                marginLabel: "边距",
                mascotCustomizeTitle: "定制你的桌面伙伴",
                workspaceMinimalistName: "极简模式",
                workspaceMinimalistDesc: "灵动岛控制、剪贴板与基础能耗管理。",
                workspaceCreatorName: "创作者",
                workspaceCreatorDesc: "录屏工作室、专业截图、文件暂存架与音频混音器。",
                workspaceDeveloperName: "开发者",
                workspaceDeveloperDesc: "命令栏、端口管理、Homebrew、AI 代理与窗口分屏。",
                workspaceFullPowerName: "全能模式",
                workspaceFullPowerDesc: "立即启用所有系统工具、清理、显示器与 HUD。",
                sandboxTitle: "互动沙盒",
                sandboxSubtitle: "开始前可以先抚摸伙伴或切换色彩搭配。",
                sandboxTryPet: "抚摸伙伴",
                sandboxTryPalette: "切换配色",
                sandboxTrySnap: "触发庆祝",
                extrasGroupTitle: "扩展与自动化",
                extrasGroupCaption: "可选的消息应用下载清理与后台整理规则。",
                copyOTPButton: "复制验证码",
                otpCopiedBadge: "已复制验证码",
                focusModeTitle: "遵循 macOS 专注模式",
                focusModeCaption: "在专注或勿扰期间保持伙伴巡游和横幅安静。",
                smartOrderTitle: "智能情境优先级",
                smartOrderCaption: "将媒体、通话、计时器与 AI 任务置于空闲模块之前。",
                momentAIReady: "AI 已就绪",
                momentCountdown: "倒计时节拍",
                momentCodeCopied: "已复制验证码",
                momentSweep: "清理建议"
            )
        case .zhTW:
            return OverhaulStrings(
                resetZoomHelp: "重設為符合視窗大小",
                previewInteractiveHint: "點擊區域以預覽",
                switcherPreviewLayoutLabel: "即時版面預覽",
                scrollPreviewCurveLabel: "回應曲線",
                snapPreviewTitle: "邊緣與角落吸附區",
                marginLabel: "邊距",
                mascotCustomizeTitle: "自訂你的桌面夥伴",
                workspaceMinimalistName: "極簡模式",
                workspaceMinimalistDesc: "動態島控制、剪貼簿與基礎電力管理。",
                workspaceCreatorName: "創作者",
                workspaceCreatorDesc: "錄影工作室、專業截圖、暫存架與音訊混音器。",
                workspaceDeveloperName: "開發者",
                workspaceDeveloperDesc: "指令列、連接埠管理、Homebrew、AI 代理與視窗排列。",
                workspaceFullPowerName: "全能模式",
                workspaceFullPowerDesc: "立即啟用所有系統工具、清理、顯示器與 HUD。",
                sandboxTitle: "互動沙盒",
                sandboxSubtitle: "開始前可先輕撫夥伴或切換配色風格。",
                sandboxTryPet: "輕撫夥伴",
                sandboxTryPalette: "切換配色",
                sandboxTrySnap: "觸發慶祝",
                extrasGroupTitle: "擴充與自動化",
                extrasGroupCaption: "可選的通訊軟體下載清理與背景整理規則。",
                copyOTPButton: "複製驗證碼",
                otpCopiedBadge: "已複製驗證碼",
                focusModeTitle: "遵循 macOS 專注模式",
                focusModeCaption: "在專注或勿擾期間保持夥伴巡遊與橫幅安靜。",
                smartOrderTitle: "智慧情境優先序",
                smartOrderCaption: "將媒體、通話、計時器與 AI 任務置於閒置模組之前。",
                momentAIReady: "AI 已就緒",
                momentCountdown: "倒數節拍",
                momentCodeCopied: "已複製驗證碼",
                momentSweep: "清理建議"
            )
        case .zhHK:
            return OverhaulStrings(
                resetZoomHelp: "重設為適合視窗大小",
                previewInteractiveHint: "點擊區域以預覽",
                switcherPreviewLayoutLabel: "即時版面預覽",
                scrollPreviewCurveLabel: "反應曲線",
                snapPreviewTitle: "邊緣與角落吸附區",
                marginLabel: "邊距",
                mascotCustomizeTitle: "自訂你嘅桌面夥伴",
                workspaceMinimalistName: "極簡模式",
                workspaceMinimalistDesc: "動態島控制、剪貼簿同基本電力管理。",
                workspaceCreatorName: "創作者",
                workspaceCreatorDesc: "錄影工作室、專業截圖、暫存架同音訊混音器。",
                workspaceDeveloperName: "開發者",
                workspaceDeveloperDesc: "指令列、連接埠管理、Homebrew、AI 代理同視窗排列。",
                workspaceFullPowerName: "全能模式",
                workspaceFullPowerDesc: "即時啟用所有系統工具、清理、顯示器同 HUD。",
                sandboxTitle: "互動沙盒",
                sandboxSubtitle: "開始前可以先輕撫夥伴或者轉下配色。",
                sandboxTryPet: "輕撫夥伴",
                sandboxTryPalette: "轉配色",
                sandboxTrySnap: "觸發慶祝",
                extrasGroupTitle: "擴充與自動化",
                extrasGroupCaption: "可選嘅通訊軟件下載清理同背景整理規則。",
                copyOTPButton: "複製驗證碼",
                otpCopiedBadge: "已複製驗證碼",
                focusModeTitle: "跟隨 macOS 專注模式",
                focusModeCaption: "喺專注或者勿擾期間保持夥伴巡遊同橫幅安靜。",
                smartOrderTitle: "智能情境優先次序",
                smartOrderCaption: "將媒體、通話、計時器同 AI 任務擺喺閒置模組前面。",
                momentAIReady: "AI 已就緒",
                momentCountdown: "倒數節拍",
                momentCodeCopied: "已複製驗證碼",
                momentSweep: "清理建議"
            )
        }
    }
}

/// Localized Wave 2 strings (Recorder Studio & Screenshot Pro).
struct OverhaulWave2Strings: Sendable {
    let studioTabTitle: String
    let cameraBubbleTitle: String
    let cameraAutoShrinkLabel: String
    let keystrokeHUDTitle: String
    let clickSFXTitle: String
    let motionBlurTitle: String
    let captionsTrackTitle: String
    let transcribeAudioButton: String
    let exportSRTButton: String
    let captionsEmptyHint: String
    let smartRedactButton: String
    let smartRedactAppliedToast: String
    let pixelRulerToolTitle: String
    let hideDesktopIconsLabel: String

    static func localized(_ language: AppLanguage) -> OverhaulWave2Strings {
        switch language {
        case .enUS:
            return OverhaulWave2Strings(
                studioTabTitle: "Studio",
                cameraBubbleTitle: "Camera bubble",
                cameraAutoShrinkLabel: "Auto-shrink near cursor",
                keystrokeHUDTitle: "Keystroke HUD",
                clickSFXTitle: "Click sound",
                motionBlurTitle: "Motion blur",
                captionsTrackTitle: "Transcript & captions",
                transcribeAudioButton: "Transcribe audio",
                exportSRTButton: "Export SRT",
                captionsEmptyHint: "Run on-device speech recognition to edit or trim by spoken lines.",
                smartRedactButton: "Smart Redact",
                smartRedactAppliedToast: "Redacted %d sensitive items",
                pixelRulerToolTitle: "Pixel ruler",
                hideDesktopIconsLabel: "Hide desktop icons in captures"
            )
        case .ru:
            return OverhaulWave2Strings(
                studioTabTitle: "Студия",
                cameraBubbleTitle: "Круглая камера",
                cameraAutoShrinkLabel: "Уменьшать рядом с курсором",
                keystrokeHUDTitle: "Клавиши на экране",
                clickSFXTitle: "Звук кликов",
                motionBlurTitle: "Размытие движения",
                captionsTrackTitle: "Титры и расшифровка",
                transcribeAudioButton: "Распознать речь",
                exportSRTButton: "Экспорт SRT",
                captionsEmptyHint: "Распознайте речь локально, чтобы править титры и вырезать паузы.",
                smartRedactButton: "Умное скрытие",
                smartRedactAppliedToast: "Скрыто объектов: %d",
                pixelRulerToolTitle: "Линейка px",
                hideDesktopIconsLabel: "Скрывать значки рабочего стола на снимках"
            )
        case .ptBR:
            return OverhaulWave2Strings(
                studioTabTitle: "Estúdio",
                cameraBubbleTitle: "Bolha da câmera",
                cameraAutoShrinkLabel: "Reduzir perto do cursor",
                keystrokeHUDTitle: "Teclas na tela",
                clickSFXTitle: "Som do clique",
                motionBlurTitle: "Desfoque de movimento",
                captionsTrackTitle: "Legendas e transcrição",
                transcribeAudioButton: "Transcrever áudio",
                exportSRTButton: "Exportar SRT",
                captionsEmptyHint: "Transcreva localmente para editar legendas e cortar trechos falados.",
                smartRedactButton: "Ocultação inteligente",
                smartRedactAppliedToast: "%d dados sensíveis ocultados",
                pixelRulerToolTitle: "Régua de pixels",
                hideDesktopIconsLabel: "Ocultar ícones da mesa nas capturas"
            )
        case .tr:
            return OverhaulWave2Strings(
                studioTabTitle: "Stüdyo",
                cameraBubbleTitle: "Kamera balonu",
                cameraAutoShrinkLabel: "İmlece yaklaşınca küçült",
                keystrokeHUDTitle: "Tuş göstergesi",
                clickSFXTitle: "Tıklama sesi",
                motionBlurTitle: "Hareket bulanıklığı",
                captionsTrackTitle: "Altyazı ve döküm",
                transcribeAudioButton: "Sesi yazıya dök",
                exportSRTButton: "SRT dışa aktar",
                captionsEmptyHint: "Cümlelere göre kesmek ve düzenlemek için cihazda konuşma tanımayı başlatın.",
                smartRedactButton: "Akıllı Gizle",
                smartRedactAppliedToast: "%d hassas öğe gizlendi",
                pixelRulerToolTitle: "Piksel cetveli",
                hideDesktopIconsLabel: "Yakalarken masaüstü simgelerini gizle"
            )
        case .es:
            return OverhaulWave2Strings(
                studioTabTitle: "Estudio",
                cameraBubbleTitle: "Burbuja de cámara",
                cameraAutoShrinkLabel: "Reducir cerca del cursor",
                keystrokeHUDTitle: "Teclas en pantalla",
                clickSFXTitle: "Sonido de clic",
                motionBlurTitle: "Desenfoque de movimiento",
                captionsTrackTitle: "Transcripción y textos",
                transcribeAudioButton: "Transcribir audio",
                exportSRTButton: "Exportar SRT",
                captionsEmptyHint: "Ejecuta el reconocimiento local para editar o recortar por frases.",
                smartRedactButton: "Censura inteligente",
                smartRedactAppliedToast: "%d elementos sensibles ocultos",
                pixelRulerToolTitle: "Regla de píxeles",
                hideDesktopIconsLabel: "Ocultar iconos del escritorio al capturar"
            )
        case .sk:
            return OverhaulWave2Strings(
                studioTabTitle: "Štúdio",
                cameraBubbleTitle: "Bublina kamery",
                cameraAutoShrinkLabel: "Zmenšiť pri kurzore",
                keystrokeHUDTitle: "Klávesy na obrazovke",
                clickSFXTitle: "Zvuk kliknutia",
                motionBlurTitle: "Rozmazanie pohybu",
                captionsTrackTitle: "Titulky a prepis",
                transcribeAudioButton: "Prepísať reč",
                exportSRTButton: "Exportovať SRT",
                captionsEmptyHint: "Spustite lokálne rozpoznávanie reči na úpravu a strih podľa viet.",
                smartRedactButton: "Chytré skrytie",
                smartRedactAppliedToast: "Skrytých položiek: %d",
                pixelRulerToolTitle: "Pixelové pravítko",
                hideDesktopIconsLabel: "Skryť ikony plochy pri snímke"
            )
        case .de:
            return OverhaulWave2Strings(
                studioTabTitle: "Studio",
                cameraBubbleTitle: "Kamera-Blase",
                cameraAutoShrinkLabel: "Am Zeiger verkleinern",
                keystrokeHUDTitle: "Tasten-HUD",
                clickSFXTitle: "Klick-Sound",
                motionBlurTitle: "Bewegungsunschärfe",
                captionsTrackTitle: "Transkript & Texte",
                transcribeAudioButton: "Audio transkribieren",
                exportSRTButton: "SRT exportieren",
                captionsEmptyHint: "Lokale Spracherkennung starten, um Textzeilen zu schneiden.",
                smartRedactButton: "Smart-Schwärzen",
                smartRedactAppliedToast: "%d sensible Bereiche verdeckt",
                pixelRulerToolTitle: "Pixel-Lineal",
                hideDesktopIconsLabel: "Schreibtischsymbole bei Aufnahmen ausblenden"
            )
        case .fr:
            return OverhaulWave2Strings(
                studioTabTitle: "Studio",
                cameraBubbleTitle: "Bulle caméra",
                cameraAutoShrinkLabel: "Réduire près du curseur",
                keystrokeHUDTitle: "Affichage des touches",
                clickSFXTitle: "Son du clic",
                motionBlurTitle: "Flou de mouvement",
                captionsTrackTitle: "Transcription et légendes",
                transcribeAudioButton: "Transcrire l\u{2019}audio",
                exportSRTButton: "Exporter SRT",
                captionsEmptyHint: "Lancez la dictée locale pour éditer ou couper par phrase.",
                smartRedactButton: "Masquage intelligent",
                smartRedactAppliedToast: "%d éléments sensibles masqués",
                pixelRulerToolTitle: "Règle en pixels",
                hideDesktopIconsLabel: "Masquer les icônes du bureau lors des captures"
            )
        case .it:
            return OverhaulWave2Strings(
                studioTabTitle: "Studio",
                cameraBubbleTitle: "Bolla webcam",
                cameraAutoShrinkLabel: "Riduci vicino al cursore",
                keystrokeHUDTitle: "Tasti su schermo",
                clickSFXTitle: "Suono clic",
                motionBlurTitle: "Sfocatura movimento",
                captionsTrackTitle: "Trascrizione e testi",
                transcribeAudioButton: "Trascrivi audio",
                exportSRTButton: "Esporta SRT",
                captionsEmptyHint: "Avvia il riconoscimento locale per tagliare o modificare le frasi.",
                smartRedactButton: "Oscura dati",
                smartRedactAppliedToast: "%d dati sensibili oscurati",
                pixelRulerToolTitle: "Righello pixel",
                hideDesktopIconsLabel: "Nascondi icone scrivania nelle catture"
            )
        case .ja:
            return OverhaulWave2Strings(
                studioTabTitle: "スタジオ",
                cameraBubbleTitle: "カメラバブル",
                cameraAutoShrinkLabel: "カーソル付近で縮小",
                keystrokeHUDTitle: "キー入力表示",
                clickSFXTitle: "クリック効果音",
                motionBlurTitle: "モーションブラー",
                captionsTrackTitle: "文字起こし・キャプション",
                transcribeAudioButton: "音声を文字起こし",
                exportSRTButton: "SRT 書き出し",
                captionsEmptyHint: "オンデバイス音声認識を実行して発話区間を編集・カットできます。",
                smartRedactButton: "スマート墨消し",
                smartRedactAppliedToast: "%d 件の機密情報を隠しました",
                pixelRulerToolTitle: "ピクセル定規",
                hideDesktopIconsLabel: "キャプチャ時にデスクトップアイコンを隠す"
            )
        case .ko:
            return OverhaulWave2Strings(
                studioTabTitle: "스튜디오",
                cameraBubbleTitle: "카메라 버블",
                cameraAutoShrinkLabel: "커서 근처에서 축소",
                keystrokeHUDTitle: "키 입력 표시",
                clickSFXTitle: "클릭 효과음",
                motionBlurTitle: "모션 블러",
                captionsTrackTitle: "전사 및 자막 트랙",
                transcribeAudioButton: "음성 받아쓰기",
                exportSRTButton: "SRT 내보내기",
                captionsEmptyHint: "기기 내 음성 인식을 실행해 발화 단위로 편집하고 자르세요.",
                smartRedactButton: "스마트 가리기",
                smartRedactAppliedToast: "민감한 항목 %d개 가림",
                pixelRulerToolTitle: "픽셀 눈금자",
                hideDesktopIconsLabel: "캡처 시 데스크톱 아이콘 숨기기"
            )
        case .uk:
            return OverhaulWave2Strings(
                studioTabTitle: "Студія",
                cameraBubbleTitle: "Бульбашка камери",
                cameraAutoShrinkLabel: "Зменшувати біля курсора",
                keystrokeHUDTitle: "Клавіші на екрані",
                clickSFXTitle: "Звук кліку",
                motionBlurTitle: "Розмиття руху",
                captionsTrackTitle: "Розшифровка й титри",
                transcribeAudioButton: "Розпізнати мову",
                exportSRTButton: "Експорт SRT",
                captionsEmptyHint: "Запустіть локальне розпізнавання мови для редагування за репліками.",
                smartRedactButton: "Розумне приховування",
                smartRedactAppliedToast: "Приховано елементів: %d",
                pixelRulerToolTitle: "Лінійка пікселів",
                hideDesktopIconsLabel: "Ховати значки робочого столу на знімках"
            )
        case .zhHans:
            return OverhaulWave2Strings(
                studioTabTitle: "工作室",
                cameraBubbleTitle: "摄像头气泡",
                cameraAutoShrinkLabel: "靠近指针时缩小",
                keystrokeHUDTitle: "按键显示",
                clickSFXTitle: "点击音效",
                motionBlurTitle: "动态模糊",
                captionsTrackTitle: "字幕与转录",
                transcribeAudioButton: "转录音频",
                exportSRTButton: "导出 SRT",
                captionsEmptyHint: "运行本地语音识别，按口述片段编辑或粗剪。",
                smartRedactButton: "智能打码",
                smartRedactAppliedToast: "已隐藏 %d 处敏感内容",
                pixelRulerToolTitle: "像素标尺",
                hideDesktopIconsLabel: "截图时隐藏桌面图标"
            )
        case .zhTW:
            return OverhaulWave2Strings(
                studioTabTitle: "工作室",
                cameraBubbleTitle: "攝影機泡泡",
                cameraAutoShrinkLabel: "靠近游標時縮小",
                keystrokeHUDTitle: "按鍵顯示",
                clickSFXTitle: "點擊音效",
                motionBlurTitle: "動態模糊",
                captionsTrackTitle: "字幕與轉錄",
                transcribeAudioButton: "轉錄音訊",
                exportSRTButton: "匯出 SRT",
                captionsEmptyHint: "執行裝置端語音辨識，依口述片段編輯或剪輯。",
                smartRedactButton: "智慧遮蔽",
                smartRedactAppliedToast: "已遮蔽 %d 項敏感資訊",
                pixelRulerToolTitle: "像素尺規",
                hideDesktopIconsLabel: "擷取時隱藏桌面圖示"
            )
        case .zhHK:
            return OverhaulWave2Strings(
                studioTabTitle: "工作室",
                cameraBubbleTitle: "鏡頭泡泡",
                cameraAutoShrinkLabel: "靠近游標時縮小",
                keystrokeHUDTitle: "按鍵顯示",
                clickSFXTitle: "點擊音效",
                motionBlurTitle: "動態模糊",
                captionsTrackTitle: "字幕與轉錄",
                transcribeAudioButton: "轉錄音訊",
                exportSRTButton: "匯出 SRT",
                captionsEmptyHint: "執行本機語音識別，按說話片段編輯同剪接。",
                smartRedactButton: "智能遮蔽",
                smartRedactAppliedToast: "已遮蔽 %d 項敏感資料",
                pixelRulerToolTitle: "像素間尺",
                hideDesktopIconsLabel: "擷取時隱藏桌面圖示"
            )
        }
    }
}

extension OverhaulStrings {
    static func wave2(_ language: AppLanguage) -> OverhaulWave2Strings {
        OverhaulWave2Strings.localized(language)
    }

    static func wave3(_ language: AppLanguage) -> OverhaulWave3Strings {
        OverhaulWave3Strings.localized(language)
    }
}

struct OverhaulWave3Strings: Equatable {
    let quickAITitle: String
    let quickAIPlaceholder: String
    let quickAIThinking: String
    let layoutListLabel: String
    let layoutSplitLabel: String
    let layoutGridLabel: String
    let pinboardAllLabel: String
    let pasteStackTitle: String
    let pasteStackCountFormat: String
    let transformMenuTitle: String
    let syncVaultTitle: String
    let parametricEQTitle: String
    let eqPresetLabel: String
    let micNoiseGateLabel: String
    let micLevelerLabel: String

    static func localized(_ language: AppLanguage) -> OverhaulWave3Strings {
        switch language {
        case .enUS:
            return OverhaulWave3Strings(
                quickAITitle: "Quick AI",
                quickAIPlaceholder: "Ask Ollama, CLI or connected model...",
                quickAIThinking: "Thinking...",
                layoutListLabel: "List",
                layoutSplitLabel: "Split Detail",
                layoutGridLabel: "Grid",
                pinboardAllLabel: "All Pinboards",
                pasteStackTitle: "Paste Stack",
                pasteStackCountFormat: "Stack: %d",
                transformMenuTitle: "Transform",
                syncVaultTitle: "Encrypted Sync Vault",
                parametricEQTitle: "10-Band Parametric EQ",
                eqPresetLabel: "EQ Profile",
                micNoiseGateLabel: "Mic Noise Gate",
                micLevelerLabel: "Auto Speech Leveler"
            )
        case .ru:
            return OverhaulWave3Strings(
                quickAITitle: "Быстрый ИИ",
                quickAIPlaceholder: "Спросите Ollama, CLI или модель...",
                quickAIThinking: "Думаю...",
                layoutListLabel: "Список",
                layoutSplitLabel: "С деталями",
                layoutGridLabel: "Сетка",
                pinboardAllLabel: "Все доски",
                pasteStackTitle: "Стек вставки",
                pasteStackCountFormat: "Стек: %d",
                transformMenuTitle: "Преобразовать",
                syncVaultTitle: "Шифрованное хранилище",
                parametricEQTitle: "10-полосный параметрический EQ",
                eqPresetLabel: "Профиль EQ",
                micNoiseGateLabel: "Шумоподавление микрофона",
                micLevelerLabel: "Выравнивание громкости речи"
            )
        case .ptBR:
            return OverhaulWave3Strings(
                quickAITitle: "IA Rapida",
                quickAIPlaceholder: "Pergunte ao Ollama, CLI ou modelo...",
                quickAIThinking: "Pensando...",
                layoutListLabel: "Lista",
                layoutSplitLabel: "Detalhe dividido",
                layoutGridLabel: "Grade",
                pinboardAllLabel: "Todos os paineis",
                pasteStackTitle: "Pilha de colagem",
                pasteStackCountFormat: "Pilha: %d",
                transformMenuTitle: "Transformar",
                syncVaultTitle: "Cofre criptografado",
                parametricEQTitle: "EQ parametrico de 10 bandas",
                eqPresetLabel: "Perfil de EQ",
                micNoiseGateLabel: "Noise gate do microfone",
                micLevelerLabel: "Nivelador de voz"
            )
        case .tr:
            return OverhaulWave3Strings(
                quickAITitle: "Hizli Yapay Zeka",
                quickAIPlaceholder: "Ollama, CLI veya bagli modele sor...",
                quickAIThinking: "Dusunuyor...",
                layoutListLabel: "Liste",
                layoutSplitLabel: "Bolunmus Detay",
                layoutGridLabel: "Izgara",
                pinboardAllLabel: "Tum Panolar",
                pasteStackTitle: "Yapistirma Yigini",
                pasteStackCountFormat: "Yigin: %d",
                transformMenuTitle: "Donustur",
                syncVaultTitle: "Sifreli Kasa",
                parametricEQTitle: "10 Bant Parametrik EQ",
                eqPresetLabel: "EQ Profili",
                micNoiseGateLabel: "Mikrofon Gurultu Kapisi",
                micLevelerLabel: "Otomatik Ses Dengeleyici"
            )
        case .es:
            return OverhaulWave3Strings(
                quickAITitle: "IA Rapida",
                quickAIPlaceholder: "Pregunta a Ollama, CLI o modelo...",
                quickAIThinking: "Pensando...",
                layoutListLabel: "Lista",
                layoutSplitLabel: "Detalle dividido",
                layoutGridLabel: "Cuadricula",
                pinboardAllLabel: "Todos los tableros",
                pasteStackTitle: "Pila de pegado",
                pasteStackCountFormat: "Pila: %d",
                transformMenuTitle: "Transformar",
                syncVaultTitle: "Boveda cifrada",
                parametricEQTitle: "Ecualizador parametrico de 10 bandas",
                eqPresetLabel: "Perfil EQ",
                micNoiseGateLabel: "Puerta de ruido del microfono",
                micLevelerLabel: "Nivelador automatico de voz"
            )
        case .sk:
            return OverhaulWave3Strings(
                quickAITitle: "Rychla AI",
                quickAIPlaceholder: "Opytajte sa Ollama, CLI alebo modelu...",
                quickAIThinking: "Rozmyslam...",
                layoutListLabel: "Zoznam",
                layoutSplitLabel: "Rozdeleny detail",
                layoutGridLabel: "Mriezka",
                pinboardAllLabel: "Vsetky nastenky",
                pasteStackTitle: "Zasobnik vkladania",
                pasteStackCountFormat: "Zasobnik: %d",
                transformMenuTitle: "Transformovat",
                syncVaultTitle: "Sifrovany trezor",
                parametricEQTitle: "10-pasmovy parametricky EQ",
                eqPresetLabel: "Profil EQ",
                micNoiseGateLabel: "Sumova brana mikrofonu",
                micLevelerLabel: "Vyrovnavanie reci"
            )
        case .de:
            return OverhaulWave3Strings(
                quickAITitle: "Schnelle KI",
                quickAIPlaceholder: "Ollama, CLI oder Modell fragen...",
                quickAIThinking: "Denke nach...",
                layoutListLabel: "Liste",
                layoutSplitLabel: "Geteilte Ansicht",
                layoutGridLabel: "Raster",
                pinboardAllLabel: "Alle Pinnwaende",
                pasteStackTitle: "Einfuege-Stapel",
                pasteStackCountFormat: "Stapel: %d",
                transformMenuTitle: "Umwandeln",
                syncVaultTitle: "Verschluesselter Tresor",
                parametricEQTitle: "10-Band-Parametrik-EQ",
                eqPresetLabel: "EQ-Profil",
                micNoiseGateLabel: "Mikrofon-Noise-Gate",
                micLevelerLabel: "Sprachpegel-Automatik"
            )
        case .fr:
            return OverhaulWave3Strings(
                quickAITitle: "IA Rapide",
                quickAIPlaceholder: "Demander a Ollama, CLI ou modele...",
                quickAIThinking: "Reflexion...",
                layoutListLabel: "Liste",
                layoutSplitLabel: "Detail partage",
                layoutGridLabel: "Grille",
                pinboardAllLabel: "Tous les tableaux",
                pasteStackTitle: "Pile de collage",
                pasteStackCountFormat: "Pile\u{00A0}: %d",
                transformMenuTitle: "Transformer",
                syncVaultTitle: "Coffre chiffre",
                parametricEQTitle: "EQ parametrique 10 bandes",
                eqPresetLabel: "Profil EQ",
                micNoiseGateLabel: "Noise gate du micro",
                micLevelerLabel: "Niveleur vocal auto"
            )
        case .it:
            return OverhaulWave3Strings(
                quickAITitle: "IA Rapida",
                quickAIPlaceholder: "Chiedi a Ollama, CLI o modello...",
                quickAIThinking: "Elaborazione...",
                layoutListLabel: "Elenco",
                layoutSplitLabel: "Dettaglio diviso",
                layoutGridLabel: "Griglia",
                pinboardAllLabel: "Tutte le bacheche",
                pasteStackTitle: "Coda incolla",
                pasteStackCountFormat: "Coda: %d",
                transformMenuTitle: "Trasforma",
                syncVaultTitle: "Cassaforte cifrata",
                parametricEQTitle: "EQ parametrico 10 bande",
                eqPresetLabel: "Profilo EQ",
                micNoiseGateLabel: "Noise gate microfono",
                micLevelerLabel: "Livellatore voce"
            )
        case .ja:
            return OverhaulWave3Strings(
                quickAITitle: "クイック AI",
                quickAIPlaceholder: "Ollama や CLI、モデルに質問...",
                quickAIThinking: "思考中...",
                layoutListLabel: "リスト",
                layoutSplitLabel: "分割詳細",
                layoutGridLabel: "グリッド",
                pinboardAllLabel: "すべて",
                pasteStackTitle: "ペーストスタック",
                pasteStackCountFormat: "スタック: %d",
                transformMenuTitle: "変換",
                syncVaultTitle: "暗号化同期ボールト",
                parametricEQTitle: "10バンド パラメトリックEQ",
                eqPresetLabel: "EQ プロファイル",
                micNoiseGateLabel: "マイク ノイズゲート",
                micLevelerLabel: "音声オートレベラー"
            )
        case .ko:
            return OverhaulWave3Strings(
                quickAITitle: "빠른 AI",
                quickAIPlaceholder: "Ollama, CLI 또는 모델에 질문...",
                quickAIThinking: "생각 중...",
                layoutListLabel: "목록",
                layoutSplitLabel: "분할 상세",
                layoutGridLabel: "그리드",
                pinboardAllLabel: "모든 보드",
                pasteStackTitle: "붙여넣기 스택",
                pasteStackCountFormat: "스택: %d",
                transformMenuTitle: "변환",
                syncVaultTitle: "암호화 동기화 보관함",
                parametricEQTitle: "10밴드 파라메트릭 EQ",
                eqPresetLabel: "EQ 프로필",
                micNoiseGateLabel: "마이크 노이즈 게이트",
                micLevelerLabel: "자동 음성 레벨러"
            )
        case .uk:
            return OverhaulWave3Strings(
                quickAITitle: "Швидкий ШІ",
                quickAIPlaceholder: "Запитайте Ollama, CLI або модель...",
                quickAIThinking: "Міркую...",
                layoutListLabel: "Список",
                layoutSplitLabel: "Із деталями",
                layoutGridLabel: "Сітка",
                pinboardAllLabel: "Усі дошки",
                pasteStackTitle: "Стек вставлення",
                pasteStackCountFormat: "Стек: %d",
                transformMenuTitle: "Перетворити",
                syncVaultTitle: "Шифроване сховище",
                parametricEQTitle: "10-смуговий параметричний EQ",
                eqPresetLabel: "Профіль EQ",
                micNoiseGateLabel: "Шумозаглушення мікрофона",
                micLevelerLabel: "Вирівнювання мовлення"
            )
        case .zhHans:
            return OverhaulWave3Strings(
                quickAITitle: "快速 AI",
                quickAIPlaceholder: "向 Ollama、CLI 或模型提问...",
                quickAIThinking: "思考中...",
                layoutListLabel: "列表",
                layoutSplitLabel: "分栏详情",
                layoutGridLabel: "网格",
                pinboardAllLabel: "全部看板",
                pasteStackTitle: "粘贴队列",
                pasteStackCountFormat: "队列: %d",
                transformMenuTitle: "格式转换",
                syncVaultTitle: "加密同步保险库",
                parametricEQTitle: "10 段参量均衡器",
                eqPresetLabel: "EQ 预设",
                micNoiseGateLabel: "麦克风噪声门",
                micLevelerLabel: "自动人声电平"
            )
        case .zhTW:
            return OverhaulWave3Strings(
                quickAITitle: "快速 AI",
                quickAIPlaceholder: "向 Ollama、CLI 或模型提問...",
                quickAIThinking: "思考中...",
                layoutListLabel: "列表",
                layoutSplitLabel: "分割詳情",
                layoutGridLabel: "格狀",
                pinboardAllLabel: "所有看板",
                pasteStackTitle: "貼上佇列",
                pasteStackCountFormat: "佇列: %d",
                transformMenuTitle: "格式轉換",
                syncVaultTitle: "加密同步保險庫",
                parametricEQTitle: "10 段參數等化器",
                eqPresetLabel: "EQ 描述檔",
                micNoiseGateLabel: "麥克風雜訊閘",
                micLevelerLabel: "自動人聲電平"
            )
        case .zhHK:
            return OverhaulWave3Strings(
                quickAITitle: "快速 AI",
                quickAIPlaceholder: "向 Ollama、CLI 或模型提問...",
                quickAIThinking: "思考緊...",
                layoutListLabel: "列表",
                layoutSplitLabel: "分欄詳情",
                layoutGridLabel: "格狀",
                pinboardAllLabel: "全部看板",
                pasteStackTitle: "貼上佇列",
                pasteStackCountFormat: "佇列: %d",
                transformMenuTitle: "轉換格式",
                syncVaultTitle: "加密同步保險庫",
                parametricEQTitle: "10 段參數均衡器",
                eqPresetLabel: "EQ 預設",
                micNoiseGateLabel: "咪高風降噪閘",
                micLevelerLabel: "自動人聲平衡"
            )
        }
    }
}

extension OverhaulStrings {
    static func wave4(_ language: AppLanguage) -> OverhaulWave4Strings {
        OverhaulWave4Strings.localized(language)
    }

    static func shelfActions(_ language: AppLanguage) -> ShelfActionStrings {
        ShelfActionStrings.localized(language)
    }
}

struct ShelfActionStrings: Equatable {
    let convertWebP: String
    let convertHEIC: String
    let mergePDF: String
    let batchRename: String

    static func localized(_ language: AppLanguage) -> ShelfActionStrings {
        let w = OverhaulWave4Strings.localized(language)
        return ShelfActionStrings(
            convertWebP: w.shelfConvertWebP,
            convertHEIC: w.shelfConvertHEIC,
            mergePDF: w.shelfMergePDF,
            batchRename: w.shelfBatchRename
        )
    }
}

struct OverhaulWave4Strings: Equatable {
    let hardwareContrastLabel: String
    let hardwareVolumeLabel: String
    let inputSourceLabel: String
    let ambientSyncLabel: String
    let virtualHiDPILabel: String
    let workspacesTitle: String
    let saveWorkspaceButton: String
    let customSnapGridLabel: String
    let shelfConvertWebP: String
    let shelfConvertHEIC: String
    let shelfMergePDF: String
    let shelfBatchRename: String
    let telemetryHorizonLabel: String
    let spaceLensTitle: String
    let trashLeftoversFoundFormat: String
    let cleanLeftoversButton: String

    static func localized(_ language: AppLanguage) -> OverhaulWave4Strings {
        switch language {
        case .enUS:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Hardware Contrast",
                hardwareVolumeLabel: "Monitor Volume",
                inputSourceLabel: "KVM Input Source",
                ambientSyncLabel: "Sync with Ambient Light Sensor",
                virtualHiDPILabel: "Virtual HiDPI Displays",
                workspacesTitle: "Window Workspaces",
                saveWorkspaceButton: "Save Current Layout",
                customSnapGridLabel: "Custom Snap Grid",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "Merge PDFs",
                shelfBatchRename: "Batch Rename",
                telemetryHorizonLabel: "History Window",
                spaceLensTitle: "Space Lens Map",
                trashLeftoversFoundFormat: "Found %d leftover files for %@ in Library",
                cleanLeftoversButton: "Sweep Leftovers"
            )
        case .ru:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Контрастность монитора",
                hardwareVolumeLabel: "Громкость монитора",
                inputSourceLabel: "Видеовход KVM",
                ambientSyncLabel: "Автояркость по датчику освещения",
                virtualHiDPILabel: "Виртуальные HiDPI-экраны",
                workspacesTitle: "Пространства окон",
                saveWorkspaceButton: "Сохранить раскладку",
                customSnapGridLabel: "Своя сетка привязки",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "Объединить PDF",
                shelfBatchRename: "Пакетное переименование",
                telemetryHorizonLabel: "Горизонт истории",
                spaceLensTitle: "Карта диска Space Lens",
                trashLeftoversFoundFormat: "Найдено %d следов %@ в Библиотеке",
                cleanLeftoversButton: "Очистить следы"
            )
        case .ptBR:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Contraste de hardware",
                hardwareVolumeLabel: "Volume do monitor",
                inputSourceLabel: "Entrada KVM",
                ambientSyncLabel: "Sincronizar com luz ambiente",
                virtualHiDPILabel: "Telas HiDPI virtuais",
                workspacesTitle: "Espacos de janelas",
                saveWorkspaceButton: "Salvar layout atual",
                customSnapGridLabel: "Grade personalizada",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "Juntar PDFs",
                shelfBatchRename: "Renomear em lote",
                telemetryHorizonLabel: "Janela de historico",
                spaceLensTitle: "Mapa Space Lens",
                trashLeftoversFoundFormat: "%d restos de %@ encontrados na Biblioteca",
                cleanLeftoversButton: "Limpar restos"
            )
        case .tr:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Donanim Kontrasti",
                hardwareVolumeLabel: "Monitor Sesi",
                inputSourceLabel: "KVM Giris Kaynagi",
                ambientSyncLabel: "Ortam isigina gore senkronize et",
                virtualHiDPILabel: "Sanal HiDPI Ekranlar",
                workspacesTitle: "Pencere Calisma Alanlari",
                saveWorkspaceButton: "Mevcut Duzeni Kaydet",
                customSnapGridLabel: "Ozel Yerlesim Izgarasi",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "PDF Birlestir",
                shelfBatchRename: "Toplu Yeniden Adlandir",
                telemetryHorizonLabel: "Gecmis Araligi",
                spaceLensTitle: "Space Lens Haritasi",
                trashLeftoversFoundFormat: "Kutuphanede %2$@ icin %1$d artik bulundu",
                cleanLeftoversButton: "Artiklari Temizle"
            )
        case .es:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Contraste por hardware",
                hardwareVolumeLabel: "Volumen del monitor",
                inputSourceLabel: "Fuente KVM",
                ambientSyncLabel: "Sincronizar con sensor de luz",
                virtualHiDPILabel: "Pantallas HiDPI virtuales",
                workspacesTitle: "Espacios de ventanas",
                saveWorkspaceButton: "Guardar disposicion",
                customSnapGridLabel: "Cuadricula personalizada",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "Unir PDFs",
                shelfBatchRename: "Renombrar en lote",
                telemetryHorizonLabel: "Ventana de historial",
                spaceLensTitle: "Mapa Space Lens",
                trashLeftoversFoundFormat: "Encontrados %d restos de %@ en Biblioteca",
                cleanLeftoversButton: "Limpiar restos"
            )
        case .sk:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Hardverovy kontrast",
                hardwareVolumeLabel: "Hlasitost monitora",
                inputSourceLabel: "KVM vstupny zdroj",
                ambientSyncLabel: "Synchronizovat so senzorom svetla",
                virtualHiDPILabel: "Virtualne HiDPI obrazovky",
                workspacesTitle: "Pracovne plochy okien",
                saveWorkspaceButton: "Ulozit aktualne rozlozenie",
                customSnapGridLabel: "Vlastna mriezka",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "Zlucit PDF",
                shelfBatchRename: "Hromadne premenovanie",
                telemetryHorizonLabel: "Rozsah historie",
                spaceLensTitle: "Mapa Space Lens",
                trashLeftoversFoundFormat: "Najdenych %d zvyskov %@ v Kniznici",
                cleanLeftoversButton: "Vymazat zvysky"
            )
        case .de:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Hardware-Kontrast",
                hardwareVolumeLabel: "Monitor-Lautstaerke",
                inputSourceLabel: "KVM-Eingangsquelle",
                ambientSyncLabel: "Mit Umgebungslicht synchronisieren",
                virtualHiDPILabel: "Virtuelle HiDPI-Displays",
                workspacesTitle: "Fenster-Arbeitsbereiche",
                saveWorkspaceButton: "Layout speichern",
                customSnapGridLabel: "Benutzerdefiniertes Raster",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "PDFs zusammenfuegen",
                shelfBatchRename: "Stapel-Umbenennung",
                telemetryHorizonLabel: "Verlaufszeitraum",
                spaceLensTitle: "Space Lens Karte",
                trashLeftoversFoundFormat: "%d Restdateien fuer %@ in Library gefunden",
                cleanLeftoversButton: "Reste entfernen"
            )
        case .fr:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Contraste materiel",
                hardwareVolumeLabel: "Volume du moniteur",
                inputSourceLabel: "Entree KVM",
                ambientSyncLabel: "Synchroniser avec la lumiere ambiante",
                virtualHiDPILabel: "Ecrans HiDPI virtuels",
                workspacesTitle: "Espaces de fenetres",
                saveWorkspaceButton: "Enregistrer la disposition",
                customSnapGridLabel: "Grille personnalisee",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "Fusionner PDF",
                shelfBatchRename: "Renommer par lot",
                telemetryHorizonLabel: "Fenetre d historique",
                spaceLensTitle: "Carte Space Lens",
                trashLeftoversFoundFormat: "%d residus de %@ trouves dans Bibliotheque",
                cleanLeftoversButton: "Nettoyer residus"
            )
        case .it:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Contrasto hardware",
                hardwareVolumeLabel: "Volume monitor",
                inputSourceLabel: "Ingresso KVM",
                ambientSyncLabel: "Sincronizza con sensore luce",
                virtualHiDPILabel: "Schermi HiDPI virtuali",
                workspacesTitle: "Spazi finestre",
                saveWorkspaceButton: "Salva layout attuale",
                customSnapGridLabel: "Griglia personalizzata",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "Unisci PDF",
                shelfBatchRename: "Rinomina in blocco",
                telemetryHorizonLabel: "Intervallo cronologia",
                spaceLensTitle: "Mappa Space Lens",
                trashLeftoversFoundFormat: "Trovati %d file residui di %@ in Libreria",
                cleanLeftoversButton: "Pulisci residui"
            )
        case .ja:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "ハードウェアコントラスト",
                hardwareVolumeLabel: "モニター音量",
                inputSourceLabel: "KVM 入力ソース",
                ambientSyncLabel: "環境光センサーと同期",
                virtualHiDPILabel: "仮想 HiDPI ディスプレイ",
                workspacesTitle: "ウィンドウワークスペース",
                saveWorkspaceButton: "現在の配置を保存",
                customSnapGridLabel: "カスタムスナップグリッド",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "PDF を結合",
                shelfBatchRename: "一括リネーム",
                telemetryHorizonLabel: "履歴ウィンドウ",
                spaceLensTitle: "Space Lens マップ",
                trashLeftoversFoundFormat: "ライブラリ内に %2$@ の関連項目が %1$d 件見つかりました",
                cleanLeftoversButton: "残余を掃除"
            )
        case .ko:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "하드웨어 명암",
                hardwareVolumeLabel: "모니터 음량",
                inputSourceLabel: "KVM 입력 소스",
                ambientSyncLabel: "주변광 센서와 동기화",
                virtualHiDPILabel: "가상 HiDPI 디스플레이",
                workspacesTitle: "창 작업 공간",
                saveWorkspaceButton: "현재 레이아웃 저장",
                customSnapGridLabel: "사용자 지정 스냅 그리드",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "PDF 병합",
                shelfBatchRename: "일괄 이름 바꾸기",
                telemetryHorizonLabel: "기록 기간",
                spaceLensTitle: "Space Lens 지도",
                trashLeftoversFoundFormat: "보관함에서 %2$@ 잔여 파일 %1$d개 발견",
                cleanLeftoversButton: "잔여 파일 정리"
            )
        case .uk:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "Апаратна контрастність",
                hardwareVolumeLabel: "Гучність монітора",
                inputSourceLabel: "Відеовхід KVM",
                ambientSyncLabel: "Автояскравість за датчиком світла",
                virtualHiDPILabel: "Віртуальні HiDPI-екрани",
                workspacesTitle: "Простори вікон",
                saveWorkspaceButton: "Зберегти розкладку",
                customSnapGridLabel: "Власна сітка прив язки",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "Об єднати PDF",
                shelfBatchRename: "Пакетне перейменування",
                telemetryHorizonLabel: "Горизонт історії",
                spaceLensTitle: "Карта диска Space Lens",
                trashLeftoversFoundFormat: "Знайдено %d залишків %@ у Бібліотеці",
                cleanLeftoversButton: "Очистити залишки"
            )
        case .zhHans:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "硬件对比度",
                hardwareVolumeLabel: "显示器音量",
                inputSourceLabel: "KVM 输入源",
                ambientSyncLabel: "与环境光传感器同步",
                virtualHiDPILabel: "虚拟 HiDPI 显示器",
                workspacesTitle: "窗口工作区",
                saveWorkspaceButton: "保存当前布局",
                customSnapGridLabel: "自定义吸附网格",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "合并 PDF",
                shelfBatchRename: "批量重命名",
                telemetryHorizonLabel: "历史范围",
                spaceLensTitle: "Space Lens 磁盘视图",
                trashLeftoversFoundFormat: "在资源库中找到 %d 个 %@ 残留项",
                cleanLeftoversButton: "清理残留"
            )
        case .zhTW:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "硬體對比度",
                hardwareVolumeLabel: "螢幕音量",
                inputSourceLabel: "KVM 輸入來源",
                ambientSyncLabel: "與環境光感測器同步",
                virtualHiDPILabel: "虛擬 HiDPI 顯示器",
                workspacesTitle: "視窗工作區",
                saveWorkspaceButton: "儲存目前版面",
                customSnapGridLabel: "自訂貼齊格線",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "合併 PDF",
                shelfBatchRename: "批次重新命名",
                telemetryHorizonLabel: "歷程區間",
                spaceLensTitle: "Space Lens 空間地圖",
                trashLeftoversFoundFormat: "在資料庫找到 %d 個 %@ 殘留項目",
                cleanLeftoversButton: "清除殘留"
            )
        case .zhHK:
            return OverhaulWave4Strings(
                hardwareContrastLabel: "硬件對比度",
                hardwareVolumeLabel: "顯示器音量",
                inputSourceLabel: "KVM 輸入來源",
                ambientSyncLabel: "與環境光感應器同步",
                virtualHiDPILabel: "虛擬 HiDPI 顯示器",
                workspacesTitle: "視窗工作區",
                saveWorkspaceButton: "儲存目前佈局",
                customSnapGridLabel: "自訂貼齊格線",
                shelfConvertWebP: "WebP",
                shelfConvertHEIC: "HEIC",
                shelfMergePDF: "合併 PDF",
                shelfBatchRename: "批次改名",
                telemetryHorizonLabel: "歷史區間",
                spaceLensTitle: "Space Lens 空間圖",
                trashLeftoversFoundFormat: "喺資料庫搵到 %d 個 %@ 殘留項目",
                cleanLeftoversButton: "清理殘留"
            )
        }
    }
}
