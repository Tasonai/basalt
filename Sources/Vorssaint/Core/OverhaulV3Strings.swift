// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized UI copy for Vorssaint Master Overhaul v3 across all 15 supported languages.
struct OverhaulV3Strings {
    // Wave 1: Calm/Pro MenuPanel & Grid Unification
    let panelDensityCalm: String
    let panelDensityPro: String

    // Wave 2: Fluid Island & Interactive Onboarding 2.0
    let onboardingMascotGreeting: String
    let onboardingRoleTitle: String
    let onboardingRoleDeveloper: String
    let onboardingRoleCreator: String
    let onboardingRoleMinimalist: String
    let onboardingRolePower: String
    let onboardingTryIsland: String
    let onboardingTryCommandBar: String
    let onboardingTryShelf: String

    // Wave 3: Audio Mixer Pro 3.0
    let audioChainTitle: String
    let audioChainSlotLabel: String
    let perAppOutputTitle: String
    let systemDefaultOutput: String
    let autoEQTitle: String
    let autoEQImportButton: String
    let loudnessToggleTitle: String

    // Wave 4: Displays Pro 3.0
    let hidpiMirrorTitle: String
    let hidpiMirrorConfirmBanner: String
    let hidpiMirrorConfirmAction: String
    let hidpiMirrorRevertAction: String
    let solarSyncToggleTitle: String
    let ddcStandbyAction: String
    let xdrPerAppRulesTitle: String

    // Wave 5: Menu Bar Icon Manager, libIOReport Watts & 7d Telemetry
    let menuBarManagerToggle: String
    let menuBarOverflowTitle: String
    let wattsPackageLabel: String
    let smartHealthTitle: String
    let telemetrySevenDayHorizon: String

    // Wave 6: Recorder 3.0 & Screenshots 3.0
    let recorderCameraShapeTitle: String
    let recorderPersonBlurToggle: String
    let recorderTilt3DToggle: String
    let recorderAspectTitle: String
    let recorderMicDuckingToggle: String
    let screenshotSocialFramesTitle: String
    let screenshotSmartGuidesToggle: String
    let screenshotCloudHistoryTitle: String
    let screenshotCloudDeleteAction: String

    // Wave 7: Clipboard 3.0 FTS5/Sync, Command Bar 3.0 & Snippets 3.0
    let clipboardFTSBadgeFormat: String
    let clipboardLiveSyncToggle: String
    let aiNewThreadButton: String
    let aiAttachImageButton: String
    let inlineAITitle: String
    let snippetsImportPackButton: String

    // Wave 8: Full-Disk Space Lens, Startup Agents, Duplicates & Clop Pro
    let spaceLensSunburstMode: String
    let spaceLensTreemapMode: String
    let spaceLensCollectTitle: String
    let spaceLensCollectTrashAll: String
    let startupAgentsTitle: String
    let duplicatesFinderTitle: String
    let clopExternalToolsBadge: String

    static func localized(_ language: AppLanguage) -> OverhaulV3Strings {
        switch language {
        case .enUS: return .enUS
        case .ru: return .ru
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

private extension OverhaulV3Strings {
    static let enUS = OverhaulV3Strings(
        panelDensityCalm: "Calm",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Move over the notch to wake your companion",
        onboardingRoleTitle: "Choose a starting setup",
        onboardingRoleDeveloper: "Developer",
        onboardingRoleCreator: "Creator",
        onboardingRoleMinimalist: "Minimalist",
        onboardingRolePower: "Full Suite",
        onboardingTryIsland: "Test Island",
        onboardingTryCommandBar: "Test Command Bar",
        onboardingTryShelf: "Test Shelf",
        audioChainTitle: "AUv3 Effect Chain",
        audioChainSlotLabel: "Slot",
        perAppOutputTitle: "Output Device",
        systemDefaultOutput: "System Default",
        autoEQTitle: "AutoEQ Headphone Profile",
        autoEQImportButton: "Import AutoEQ .txt…",
        loudnessToggleTitle: "Fletcher-Munson Loudness",
        hidpiMirrorTitle: "HiDPI Virtual Mirror",
        hidpiMirrorConfirmBanner: "Keep this HiDPI display mode? Reverting automatically…",
        hidpiMirrorConfirmAction: "Keep Mode",
        hidpiMirrorRevertAction: "Revert Now",
        solarSyncToggleTitle: "Solar Brightness Curve",
        ddcStandbyAction: "Display Standby (DDC)",
        xdrPerAppRulesTitle: "Auto XDR for Frontmost App",
        menuBarManagerToggle: "Menu Bar Icon Manager",
        menuBarOverflowTitle: "Hidden Menu Bar Icons",
        wattsPackageLabel: "Package W",
        smartHealthTitle: "NVMe S.M.A.R.T. Health",
        telemetrySevenDayHorizon: "7d",
        recorderCameraShapeTitle: "Camera Frame",
        recorderPersonBlurToggle: "Portrait Background Blur",
        recorderTilt3DToggle: "3D Cursor Perspective",
        recorderAspectTitle: "Output Aspect",
        recorderMicDuckingToggle: "Auto-Duck System Audio",
        screenshotSocialFramesTitle: "Canvas Aspect Frame",
        screenshotSmartGuidesToggle: "Magnetic Smart Guides",
        screenshotCloudHistoryTitle: "Cloud Upload History",
        screenshotCloudDeleteAction: "Delete from Cloud",
        clipboardFTSBadgeFormat: "FTS5 · %d items",
        clipboardLiveSyncToggle: "Live iCloud Vault Sync",
        aiNewThreadButton: "New Chat",
        aiAttachImageButton: "Attach Clipboard Image",
        inlineAITitle: "Inline AI Selection",
        snippetsImportPackButton: "Import / Export Pack…",
        spaceLensSunburstMode: "Sunburst",
        spaceLensTreemapMode: "Treemap",
        spaceLensCollectTitle: "Collect Basket",
        spaceLensCollectTrashAll: "Trash Collected",
        startupAgentsTitle: "Startup Agents",
        duplicatesFinderTitle: "Duplicates",
        clopExternalToolsBadge: "Clop CLI Codecs"
    )

    static let ru = OverhaulV3Strings(
        panelDensityCalm: "Спокойно",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Наведите курсор на вырез, чтобы разбудить компаньона",
        onboardingRoleTitle: "Выберите стартовый профиль",
        onboardingRoleDeveloper: "Разработчик",
        onboardingRoleCreator: "Креатор",
        onboardingRoleMinimalist: "Минималист",
        onboardingRolePower: "Всё сразу",
        onboardingTryIsland: "Проверить остров",
        onboardingTryCommandBar: "Проверить панель",
        onboardingTryShelf: "Проверить полку",
        audioChainTitle: "Цепочка AUv3",
        audioChainSlotLabel: "Слот",
        perAppOutputTitle: "Выход звука",
        systemDefaultOutput: "Системный выход",
        autoEQTitle: "Профиль наушников AutoEQ",
        autoEQImportButton: "Импорт AutoEQ .txt…",
        loudnessToggleTitle: "Тонкомпенсация Loudness",
        hidpiMirrorTitle: "HiDPI-зеркало монитора",
        hidpiMirrorConfirmBanner: "Оставить режим HiDPI? Автоматический откат…",
        hidpiMirrorConfirmAction: "Сохранить",
        hidpiMirrorRevertAction: "Откатить",
        solarSyncToggleTitle: "Солнечная кривая яркости",
        ddcStandbyAction: "Усыпить экран (DDC)",
        xdrPerAppRulesTitle: "Авто-XDR для активных приложений",
        menuBarManagerToggle: "Менеджер иконок меню-бара",
        menuBarOverflowTitle: "Скрытые иконки меню-бара",
        wattsPackageLabel: "Мощность W",
        smartHealthTitle: "Ресурс NVMe S.M.A.R.T.",
        telemetrySevenDayHorizon: "7д",
        recorderCameraShapeTitle: "Форма камеры",
        recorderPersonBlurToggle: "Размытие фона портрета",
        recorderTilt3DToggle: "3D-наклон за курсором",
        recorderAspectTitle: "Формат кадра",
        recorderMicDuckingToggle: "Авто-приглушение при речи",
        screenshotSocialFramesTitle: "Пресет кадра",
        screenshotSmartGuidesToggle: "Магнитные направляющие",
        screenshotCloudHistoryTitle: "История загрузок в облако",
        screenshotCloudDeleteAction: "Удалить из облака",
        clipboardFTSBadgeFormat: "FTS5 · %d шт.",
        clipboardLiveSyncToggle: "Живая синхронизация iCloud Vault",
        aiNewThreadButton: "Новый чат",
        aiAttachImageButton: "Прикрепить снимок из буфера",
        inlineAITitle: "ИИ над выделением",
        snippetsImportPackButton: "Импорт / экспорт набора…",
        spaceLensSunburstMode: "Солнце",
        spaceLensTreemapMode: "Плитки",
        spaceLensCollectTitle: "Корзина отбора",
        spaceLensCollectTrashAll: "Удалить выбранное",
        startupAgentsTitle: "Автозапуск",
        duplicatesFinderTitle: "Дубликаты",
        clopExternalToolsBadge: "CLI-кодеки Clop"
    )

    static let ptBR = OverhaulV3Strings(
        panelDensityCalm: "Calmo",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Passe sobre o entalhe para acordar o mascote",
        onboardingRoleTitle: "Escolha uma configuração inicial",
        onboardingRoleDeveloper: "Desenvolvedor",
        onboardingRoleCreator: "Criador",
        onboardingRoleMinimalist: "Minimalista",
        onboardingRolePower: "Completo",
        onboardingTryIsland: "Testar Ilha",
        onboardingTryCommandBar: "Testar Barra",
        onboardingTryShelf: "Testar Prateleira",
        audioChainTitle: "Cadeia AUv3",
        audioChainSlotLabel: "Slot",
        perAppOutputTitle: "Dispositivo de saída",
        systemDefaultOutput: "Padrão do Sistema",
        autoEQTitle: "Perfil AutoEQ para fones",
        autoEQImportButton: "Importar AutoEQ .txt…",
        loudnessToggleTitle: "Compensação Loudness",
        hidpiMirrorTitle: "Espelho Virtual HiDPI",
        hidpiMirrorConfirmBanner: "Manter este modo HiDPI? Revertendo automaticamente…",
        hidpiMirrorConfirmAction: "Manter",
        hidpiMirrorRevertAction: "Reverter",
        solarSyncToggleTitle: "Curva solar de brilho",
        ddcStandbyAction: "Suspender tela (DDC)",
        xdrPerAppRulesTitle: "XDR automático por aplicativo",
        menuBarManagerToggle: "Gerenciador da barra de menus",
        menuBarOverflowTitle: "Ícones ocultos da barra",
        wattsPackageLabel: "Consumo W",
        smartHealthTitle: "Saúde NVMe S.M.A.R.T.",
        telemetrySevenDayHorizon: "7d",
        recorderCameraShapeTitle: "Formato da câmera",
        recorderPersonBlurToggle: "Desfoque de fundo",
        recorderTilt3DToggle: "Perspectiva 3D do cursor",
        recorderAspectTitle: "Proporção do vídeo",
        recorderMicDuckingToggle: "Atenuar áudio ao falar",
        screenshotSocialFramesTitle: "Proporção da tela",
        screenshotSmartGuidesToggle: "Guias magnéticas",
        screenshotCloudHistoryTitle: "Histórico na nuvem",
        screenshotCloudDeleteAction: "Excluir da nuvem",
        clipboardFTSBadgeFormat: "FTS5 · %d itens",
        clipboardLiveSyncToggle: "Sincronização iCloud Vault",
        aiNewThreadButton: "Novo chat",
        aiAttachImageButton: "Anexar imagem copiada",
        inlineAITitle: "IA na seleção",
        snippetsImportPackButton: "Importar / exportar pacote…",
        spaceLensSunburstMode: "Radial",
        spaceLensTreemapMode: "Blocos",
        spaceLensCollectTitle: "Cesta Collect",
        spaceLensCollectTrashAll: "Mover coletados",
        startupAgentsTitle: "Inicialização",
        duplicatesFinderTitle: "Duplicados",
        clopExternalToolsBadge: "Codecs Clop CLI"
    )

    static let tr = OverhaulV3Strings(
        panelDensityCalm: "Sakin",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Yardımcıyı uyandırmak için çentiğin üzerine gelin",
        onboardingRoleTitle: "Bir başlangıç profili seçin",
        onboardingRoleDeveloper: "Geliştirici",
        onboardingRoleCreator: "Üretici",
        onboardingRoleMinimalist: "Minimalist",
        onboardingRolePower: "Tam Paket",
        onboardingTryIsland: "Adayı Dene",
        onboardingTryCommandBar: "Komut Çubuğu",
        onboardingTryShelf: "Rafı Dene",
        audioChainTitle: "AUv3 Efekt Zinciri",
        audioChainSlotLabel: "Yuva",
        perAppOutputTitle: "Çıkış Aygıtı",
        systemDefaultOutput: "Sistem Varsayılanı",
        autoEQTitle: "AutoEQ Kulaklık Profili",
        autoEQImportButton: "AutoEQ .txt İçe Aktar…",
        loudnessToggleTitle: "Fletcher-Munson Loudness",
        hidpiMirrorTitle: "HiDPI Sanal Yansıtma",
        hidpiMirrorConfirmBanner: "Bu HiDPI modu korunsun mu? Otomatik geri dönülüyor…",
        hidpiMirrorConfirmAction: "Koru",
        hidpiMirrorRevertAction: "Geri Al",
        solarSyncToggleTitle: "Güneş Parlaklık Eğrisi",
        ddcStandbyAction: "Ekranı Uyut (DDC)",
        xdrPerAppRulesTitle: "Ön Uygulama İçin Oto XDR",
        menuBarManagerToggle: "Menü Çubuğu Simge Yöneticisi",
        menuBarOverflowTitle: "Gizli Menü Çubuğu Simgeleri",
        wattsPackageLabel: "Güç W",
        smartHealthTitle: "NVMe S.M.A.R.T. Sağlığı",
        telemetrySevenDayHorizon: "7g",
        recorderCameraShapeTitle: "Kamera Çerçevesi",
        recorderPersonBlurToggle: "Portre Arka Plan Bulanıklığı",
        recorderTilt3DToggle: "3B İmleç Perspektifi",
        recorderAspectTitle: "Çıkış Oranı",
        recorderMicDuckingToggle: "Konuşmada Sesi Kıs",
        screenshotSocialFramesTitle: "Tuval En Boy Oranı",
        screenshotSmartGuidesToggle: "Manyetik Hizalama",
        screenshotCloudHistoryTitle: "Bulut Yükleme Geçmişi",
        screenshotCloudDeleteAction: "Buluttan Sil",
        clipboardFTSBadgeFormat: "FTS5 · %d öğe",
        clipboardLiveSyncToggle: "Canlı iCloud Vault Eşitleme",
        aiNewThreadButton: "Yeni Sohbet",
        aiAttachImageButton: "Pano Görseli Ekle",
        inlineAITitle: "Seçimde Yapay Zeka",
        snippetsImportPackButton: "Paketi İçe / Dışa Aktar…",
        spaceLensSunburstMode: "Halka",
        spaceLensTreemapMode: "Ağaç Haritası",
        spaceLensCollectTitle: "Collect Sepeti",
        spaceLensCollectTrashAll: "Toplananları Sil",
        startupAgentsTitle: "Başlangıç Öğeleri",
        duplicatesFinderTitle: "Yinelenenler",
        clopExternalToolsBadge: "Clop CLI Kodekleri"
    )

    static let es = OverhaulV3Strings(
        panelDensityCalm: "Calma",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Pasa por el notch para despertar a tu compañero",
        onboardingRoleTitle: "Elige una configuración inicial",
        onboardingRoleDeveloper: "Desarrollador",
        onboardingRoleCreator: "Creador",
        onboardingRoleMinimalist: "Minimalista",
        onboardingRolePower: "Completo",
        onboardingTryIsland: "Probar Isla",
        onboardingTryCommandBar: "Probar Barra",
        onboardingTryShelf: "Probar Estante",
        audioChainTitle: "Cadena AUv3",
        audioChainSlotLabel: "Ranura",
        perAppOutputTitle: "Dispositivo de salida",
        systemDefaultOutput: "Predeterminado",
        autoEQTitle: "Perfil AutoEQ de auriculares",
        autoEQImportButton: "Importar AutoEQ .txt…",
        loudnessToggleTitle: "Compensación Loudness",
        hidpiMirrorTitle: "Espejo Virtual HiDPI",
        hidpiMirrorConfirmBanner: "¿Mantener este modo HiDPI? Revirtiendo automáticamente…",
        hidpiMirrorConfirmAction: "Mantener",
        hidpiMirrorRevertAction: "Revertir",
        solarSyncToggleTitle: "Curva solar de brillo",
        ddcStandbyAction: "Reposo del monitor (DDC)",
        xdrPerAppRulesTitle: "XDR automático por app",
        menuBarManagerToggle: "Gestor de iconos del menú",
        menuBarOverflowTitle: "Iconos ocultos del menú",
        wattsPackageLabel: "Consumo W",
        smartHealthTitle: "Salud NVMe S.M.A.R.T.",
        telemetrySevenDayHorizon: "7d",
        recorderCameraShapeTitle: "Forma de cámara",
        recorderPersonBlurToggle: "Desenfoque de fondo",
        recorderTilt3DToggle: "Perspectiva 3D del cursor",
        recorderAspectTitle: "Relación de aspecto",
        recorderMicDuckingToggle: "Atenuar audio al hablar",
        screenshotSocialFramesTitle: "Marco de relación",
        screenshotSmartGuidesToggle: "Guías inteligentes",
        screenshotCloudHistoryTitle: "Historial en la nube",
        screenshotCloudDeleteAction: "Eliminar de la nube",
        clipboardFTSBadgeFormat: "FTS5 · %d elem.",
        clipboardLiveSyncToggle: "Sincronización iCloud Vault",
        aiNewThreadButton: "Nuevo chat",
        aiAttachImageButton: "Adjuntar imagen copiada",
        inlineAITitle: "IA sobre selección",
        snippetsImportPackButton: "Importar / exportar paquete…",
        spaceLensSunburstMode: "Radial",
        spaceLensTreemapMode: "Mapa",
        spaceLensCollectTitle: "Cesta Collect",
        spaceLensCollectTrashAll: "Eliminar recogidos",
        startupAgentsTitle: "Inicio automático",
        duplicatesFinderTitle: "Duplicados",
        clopExternalToolsBadge: "Códecs Clop CLI"
    )

    static let sk = OverhaulV3Strings(
        panelDensityCalm: "Pokojne",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Prejdite ponad výrez a prebuďte spoločníka",
        onboardingRoleTitle: "Vyberte štartovací profil",
        onboardingRoleDeveloper: "Vývojár",
        onboardingRoleCreator: "Tvorca",
        onboardingRoleMinimalist: "Minimalista",
        onboardingRolePower: "Plná výbava",
        onboardingTryIsland: "Skúsiť ostrov",
        onboardingTryCommandBar: "Skúsiť lištu",
        onboardingTryShelf: "Skúsiť policu",
        audioChainTitle: "Reťazec AUv3",
        audioChainSlotLabel: "Slot",
        perAppOutputTitle: "Výstupné zariadenie",
        systemDefaultOutput: "Predvolené systémom",
        autoEQTitle: "AutoEQ profil slúchadiel",
        autoEQImportButton: "Importovať AutoEQ .txt…",
        loudnessToggleTitle: "Fyziologické zosilnenie",
        hidpiMirrorTitle: "HiDPI virtuálne zrkadlo",
        hidpiMirrorConfirmBanner: "Ponechať režim HiDPI? Automatický návrat…",
        hidpiMirrorConfirmAction: "Ponechať",
        hidpiMirrorRevertAction: "Vrátiť späť",
        solarSyncToggleTitle: "Solárna krivka jasu",
        ddcStandbyAction: "Uspať displej (DDC)",
        xdrPerAppRulesTitle: "Auto XDR pre aktívnu aplikáciu",
        menuBarManagerToggle: "Správca ikon menu lišty",
        menuBarOverflowTitle: "Skryté ikony menu lišty",
        wattsPackageLabel: "Príkon W",
        smartHealthTitle: "Stav NVMe S.M.A.R.T.",
        telemetrySevenDayHorizon: "7d",
        recorderCameraShapeTitle: "Tvar kamery",
        recorderPersonBlurToggle: "Rozostrenie pozadia",
        recorderTilt3DToggle: "3D náklon kurzora",
        recorderAspectTitle: "Pomer strán",
        recorderMicDuckingToggle: "Stlmiť zvuk pri reči",
        screenshotSocialFramesTitle: "Pomer plátna",
        screenshotSmartGuidesToggle: "Magnetické vodidlá",
        screenshotCloudHistoryTitle: "História cloudu",
        screenshotCloudDeleteAction: "Zmazať z cloudu",
        clipboardFTSBadgeFormat: "FTS5 · %d položiek",
        clipboardLiveSyncToggle: "Živá iCloud Vault synchronizácia",
        aiNewThreadButton: "Nový chat",
        aiAttachImageButton: "Priložiť obrázok zo schránky",
        inlineAITitle: "AI nad výberom",
        snippetsImportPackButton: "Import / export balíka…",
        spaceLensSunburstMode: "Kruh",
        spaceLensTreemapMode: "Dlaždice",
        spaceLensCollectTitle: "Košík Collect",
        spaceLensCollectTrashAll: "Vymazať vybrané",
        startupAgentsTitle: "Po spustení",
        duplicatesFinderTitle: "Duplicity",
        clopExternalToolsBadge: "Clop CLI kodeky"
    )

    static let de = OverhaulV3Strings(
        panelDensityCalm: "Ruhig",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Über die Notch fahren, um den Begleiter zu wecken",
        onboardingRoleTitle: "Start-Setup wählen",
        onboardingRoleDeveloper: "Entwickler",
        onboardingRoleCreator: "Creator",
        onboardingRoleMinimalist: "Minimalist",
        onboardingRolePower: "Komplett",
        onboardingTryIsland: "Insel testen",
        onboardingTryCommandBar: "Befehlsleiste testen",
        onboardingTryShelf: "Ablage testen",
        audioChainTitle: "AUv3-Effektkette",
        audioChainSlotLabel: "Slot",
        perAppOutputTitle: "Ausgabegerät",
        systemDefaultOutput: "Systemstandard",
        autoEQTitle: "AutoEQ-Kopfhörerprofil",
        autoEQImportButton: "AutoEQ .txt importieren…",
        loudnessToggleTitle: "Fletcher-Munson-Loudness",
        hidpiMirrorTitle: "Virtueller HiDPI-Spiegel",
        hidpiMirrorConfirmBanner: "Diesen HiDPI-Modus behalten? Automatische Rückkehr…",
        hidpiMirrorConfirmAction: "Behalten",
        hidpiMirrorRevertAction: "Zurücksetzen",
        solarSyncToggleTitle: "Solare Helligkeitskurve",
        ddcStandbyAction: "Display-Standby (DDC)",
        xdrPerAppRulesTitle: "Auto-XDR für aktive App",
        menuBarManagerToggle: "Menüleisten-Icon-Manager",
        menuBarOverflowTitle: "Verborgene Menüleisten-Icons",
        wattsPackageLabel: "Leistung W",
        smartHealthTitle: "NVMe S.M.A.R.T.-Zustand",
        telemetrySevenDayHorizon: "7T",
        recorderCameraShapeTitle: "Kamerarahmen",
        recorderPersonBlurToggle: "Hintergrundunschärfe",
        recorderTilt3DToggle: "3D-Cursor-Perspektive",
        recorderAspectTitle: "Seitenverhältnis",
        recorderMicDuckingToggle: "Systemton bei Sprache absenken",
        screenshotSocialFramesTitle: "Canvas-Seitenverhältnis",
        screenshotSmartGuidesToggle: "Magnetische Hilfslinien",
        screenshotCloudHistoryTitle: "Cloud-Verlauf",
        screenshotCloudDeleteAction: "Aus Cloud löschen",
        clipboardFTSBadgeFormat: "FTS5 · %d Einträge",
        clipboardLiveSyncToggle: "Live iCloud Vault Sync",
        aiNewThreadButton: "Neuer Chat",
        aiAttachImageButton: "Zwischenablage-Bild anhängen",
        inlineAITitle: "Inline-KI für Auswahl",
        snippetsImportPackButton: "Paket importieren / exportieren…",
        spaceLensSunburstMode: "Ring",
        spaceLensTreemapMode: "Kacheln",
        spaceLensCollectTitle: "Sammelkorb",
        spaceLensCollectTrashAll: "Gesammelte löschen",
        startupAgentsTitle: "Startobjekte",
        duplicatesFinderTitle: "Duplikate",
        clopExternalToolsBadge: "Clop CLI-Codecs"
    )

    static let fr = OverhaulV3Strings(
        panelDensityCalm: "Calme",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Survolez l\u{2019}encoche pour réveiller votre compagnon",
        onboardingRoleTitle: "Choisir une configuration de départ",
        onboardingRoleDeveloper: "Développeur",
        onboardingRoleCreator: "Créateur",
        onboardingRoleMinimalist: "Minimaliste",
        onboardingRolePower: "Suite complète",
        onboardingTryIsland: "Tester l\u{2019}îlot",
        onboardingTryCommandBar: "Tester la barre",
        onboardingTryShelf: "Tester l\u{2019}étagère",
        audioChainTitle: "Chaîne AUv3",
        audioChainSlotLabel: "Emplacement",
        perAppOutputTitle: "Périphérique de sortie",
        systemDefaultOutput: "Sortie système",
        autoEQTitle: "Profil casque AutoEQ",
        autoEQImportButton: "Importer AutoEQ .txt…",
        loudnessToggleTitle: "Correction Loudness",
        hidpiMirrorTitle: "Miroir virtuel HiDPI",
        hidpiMirrorConfirmBanner: "Conserver ce mode HiDPI\u{00A0}? Retour automatique…",
        hidpiMirrorConfirmAction: "Conserver",
        hidpiMirrorRevertAction: "Rétablir",
        solarSyncToggleTitle: "Courbe solaire de luminosité",
        ddcStandbyAction: "Veille écran (DDC)",
        xdrPerAppRulesTitle: "XDR auto par application",
        menuBarManagerToggle: "Gestionnaire d\u{2019}icônes",
        menuBarOverflowTitle: "Icônes masquées",
        wattsPackageLabel: "Puissance W",
        smartHealthTitle: "État NVMe S.M.A.R.T.",
        telemetrySevenDayHorizon: "7j",
        recorderCameraShapeTitle: "Cadre caméra",
        recorderPersonBlurToggle: "Flou d\u{2019}arrière-plan portrait",
        recorderTilt3DToggle: "Perspective 3D du curseur",
        recorderAspectTitle: "Format de sortie",
        recorderMicDuckingToggle: "Atténuer le son système",
        screenshotSocialFramesTitle: "Format du canevas",
        screenshotSmartGuidesToggle: "Repères magnétiques",
        screenshotCloudHistoryTitle: "Historique cloud",
        screenshotCloudDeleteAction: "Supprimer du cloud",
        clipboardFTSBadgeFormat: "FTS5 · %d éléments",
        clipboardLiveSyncToggle: "Sync iCloud Vault en direct",
        aiNewThreadButton: "Nouveau fil",
        aiAttachImageButton: "Joindre l\u{2019}image copiée",
        inlineAITitle: "IA sur la sélection",
        snippetsImportPackButton: "Importer / exporter…",
        spaceLensSunburstMode: "Soleil",
        spaceLensTreemapMode: "Mosaïque",
        spaceLensCollectTitle: "Panier Collect",
        spaceLensCollectTrashAll: "Supprimer la sélection",
        startupAgentsTitle: "Démarrage",
        duplicatesFinderTitle: "Doublons",
        clopExternalToolsBadge: "Codecs Clop CLI"
    )

    static let it = OverhaulV3Strings(
        panelDensityCalm: "Calmo",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Passa sul notch per svegliare il compagno",
        onboardingRoleTitle: "Scegli una configurazione iniziale",
        onboardingRoleDeveloper: "Sviluppatore",
        onboardingRoleCreator: "Creator",
        onboardingRoleMinimalist: "Minimalista",
        onboardingRolePower: "Suite completa",
        onboardingTryIsland: "Prova Isola",
        onboardingTryCommandBar: "Prova Barra",
        onboardingTryShelf: "Prova Mensola",
        audioChainTitle: "Catena AUv3",
        audioChainSlotLabel: "Slot",
        perAppOutputTitle: "Dispositivo di uscita",
        systemDefaultOutput: "Predefinito di sistema",
        autoEQTitle: "Profilo cuffie AutoEQ",
        autoEQImportButton: "Importa AutoEQ .txt…",
        loudnessToggleTitle: "Compensazione Loudness",
        hidpiMirrorTitle: "Mirror virtuale HiDPI",
        hidpiMirrorConfirmBanner: "Mantenere questa modalità HiDPI? Ripristino automatico…",
        hidpiMirrorConfirmAction: "Mantieni",
        hidpiMirrorRevertAction: "Ripristina",
        solarSyncToggleTitle: "Curva solare luminosità",
        ddcStandbyAction: "Standby schermo (DDC)",
        xdrPerAppRulesTitle: "XDR auto per app attiva",
        menuBarManagerToggle: "Gestore icone barra menu",
        menuBarOverflowTitle: "Icone nascoste barra menu",
        wattsPackageLabel: "Potenza W",
        smartHealthTitle: "Salute NVMe S.M.A.R.T.",
        telemetrySevenDayHorizon: "7g",
        recorderCameraShapeTitle: "Forma webcam",
        recorderPersonBlurToggle: "Sfocatura sfondo ritratto",
        recorderTilt3DToggle: "Prospettiva 3D cursore",
        recorderAspectTitle: "Proporzioni uscita",
        recorderMicDuckingToggle: "Attenua audio di sistema",
        screenshotSocialFramesTitle: "Proporzioni tela",
        screenshotSmartGuidesToggle: "Guide magnetiche",
        screenshotCloudHistoryTitle: "Cronologia cloud",
        screenshotCloudDeleteAction: "Elimina dal cloud",
        clipboardFTSBadgeFormat: "FTS5 · %d elementi",
        clipboardLiveSyncToggle: "Sync iCloud Vault live",
        aiNewThreadButton: "Nuova chat",
        aiAttachImageButton: "Allega immagine appunti",
        inlineAITitle: "IA sulla selezione",
        snippetsImportPackButton: "Importa / esporta pacchetto…",
        spaceLensSunburstMode: "Radiale",
        spaceLensTreemapMode: "Mappa",
        spaceLensCollectTitle: "Cestino Collect",
        spaceLensCollectTrashAll: "Elimina raccolti",
        startupAgentsTitle: "Avvio automatico",
        duplicatesFinderTitle: "Duplicati",
        clopExternalToolsBadge: "Codec Clop CLI"
    )

    static let ja = OverhaulV3Strings(
        panelDensityCalm: "シンプル",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "ノッチにカーソルを合わせてコンパニオンを起こす",
        onboardingRoleTitle: "スタート構成を選択",
        onboardingRoleDeveloper: "開発者",
        onboardingRoleCreator: "クリエイター",
        onboardingRoleMinimalist: "ミニマリスト",
        onboardingRolePower: "フル機能",
        onboardingTryIsland: "アイランドを試す",
        onboardingTryCommandBar: "コマンドバーを試す",
        onboardingTryShelf: "シェルフを試す",
        audioChainTitle: "AUv3 エフェクトチェーン",
        audioChainSlotLabel: "スロット",
        perAppOutputTitle: "出力デバイス",
        systemDefaultOutput: "システムデフォルト",
        autoEQTitle: "AutoEQ ヘッドホンプロファイル",
        autoEQImportButton: "AutoEQ .txt を読み込む…",
        loudnessToggleTitle: "ラウドネス補正",
        hidpiMirrorTitle: "HiDPI 仮想ミラー",
        hidpiMirrorConfirmBanner: "この HiDPI 表示を維持しますか？自動で元に戻ります…",
        hidpiMirrorConfirmAction: "維持",
        hidpiMirrorRevertAction: "今すぐ戻す",
        solarSyncToggleTitle: "太陽高度連動ブライトネス",
        ddcStandbyAction: "モニター待機 (DDC)",
        xdrPerAppRulesTitle: "前面アプリ自動 XDR",
        menuBarManagerToggle: "メニューバーアイコン管理",
        menuBarOverflowTitle: "非表示メニューバーアイコン",
        wattsPackageLabel: "消費電力 W",
        smartHealthTitle: "NVMe S.M.A.R.T. 状態",
        telemetrySevenDayHorizon: "7日",
        recorderCameraShapeTitle: "カメラフレーム",
        recorderPersonBlurToggle: "背景ポートレートぼかし",
        recorderTilt3DToggle: "3D カーソル遠近感",
        recorderAspectTitle: "出力アスペクト比",
        recorderMicDuckingToggle: "発話中システム音量を下げる",
        screenshotSocialFramesTitle: "キャンバス比率",
        screenshotSmartGuidesToggle: "スマートガイド吸着",
        screenshotCloudHistoryTitle: "クラウド履歴",
        screenshotCloudDeleteAction: "クラウドから削除",
        clipboardFTSBadgeFormat: "FTS5 · %d 件",
        clipboardLiveSyncToggle: "iCloud Vault ライブ同期",
        aiNewThreadButton: "新規チャット",
        aiAttachImageButton: "クリップボード画像を添付",
        inlineAITitle: "選択テキスト AI",
        snippetsImportPackButton: "パックを読み込み / 書き出し…",
        spaceLensSunburstMode: "サンバースト",
        spaceLensTreemapMode: "ツリーマップ",
        spaceLensCollectTitle: "Collect バスケット",
        spaceLensCollectTrashAll: "収集項目をゴミ箱へ",
        startupAgentsTitle: "起動項目",
        duplicatesFinderTitle: "重複ファイル",
        clopExternalToolsBadge: "Clop CLI コーデック"
    )

    static let ko = OverhaulV3Strings(
        panelDensityCalm: "차분함",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "노치 위로 마우스를 올려 컴패니언을 깨우세요",
        onboardingRoleTitle: "시작 구성 선택",
        onboardingRoleDeveloper: "개발자",
        onboardingRoleCreator: "크리에이터",
        onboardingRoleMinimalist: "미니멀",
        onboardingRolePower: "전체 기능",
        onboardingTryIsland: "아일랜드 체험",
        onboardingTryCommandBar: "커맨드 바 체험",
        onboardingTryShelf: "선반 체험",
        audioChainTitle: "AUv3 이펙트 체인",
        audioChainSlotLabel: "슬롯",
        perAppOutputTitle: "출력 장치",
        systemDefaultOutput: "시스템 기본값",
        autoEQTitle: "AutoEQ 헤드폰 프로필",
        autoEQImportButton: "AutoEQ .txt 가져오기…",
        loudnessToggleTitle: "라우드니스 보정",
        hidpiMirrorTitle: "HiDPI 가상 미러",
        hidpiMirrorConfirmBanner: "이 HiDPI 모드를 유지할까요? 자동으로 되돌립니다…",
        hidpiMirrorConfirmAction: "유지",
        hidpiMirrorRevertAction: "지금 되돌리기",
        solarSyncToggleTitle: "태양 고도 밝기 곡선",
        ddcStandbyAction: "모니터 절전 (DDC)",
        xdrPerAppRulesTitle: "활성 앱 자동 XDR",
        menuBarManagerToggle: "메뉴 막대 아이콘 관리자",
        menuBarOverflowTitle: "숨겨진 메뉴 막대 아이콘",
        wattsPackageLabel: "전력 W",
        smartHealthTitle: "NVMe S.M.A.R.T. 상태",
        telemetrySevenDayHorizon: "7일",
        recorderCameraShapeTitle: "카메라 프레임",
        recorderPersonBlurToggle: "인물 배경 흐림",
        recorderTilt3DToggle: "3D 커서 원근감",
        recorderAspectTitle: "출력 화면 비율",
        recorderMicDuckingToggle: "발화 시 시스템 오디오 낮춤",
        screenshotSocialFramesTitle: "캔버스 비율",
        screenshotSmartGuidesToggle: "스마트 정렬 가이드",
        screenshotCloudHistoryTitle: "클라우드 업로드 기록",
        screenshotCloudDeleteAction: "클라우드에서 삭제",
        clipboardFTSBadgeFormat: "FTS5 · %d개",
        clipboardLiveSyncToggle: "실시간 iCloud Vault 동기화",
        aiNewThreadButton: "새 대화",
        aiAttachImageButton: "클립보드 이미지 첨부",
        inlineAITitle: "선택 텍스트 AI",
        snippetsImportPackButton: "팩 가져오기 / 내보내기…",
        spaceLensSunburstMode: "선버스트",
        spaceLensTreemapMode: "트리맵",
        spaceLensCollectTitle: "Collect 바구니",
        spaceLensCollectTrashAll: "수집 항목 휴지통으로",
        startupAgentsTitle: "시작 에이전트",
        duplicatesFinderTitle: "중복 파일",
        clopExternalToolsBadge: "Clop CLI 코덱"
    )

    static let uk = OverhaulV3Strings(
        panelDensityCalm: "Спокійно",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "Наведіть курсор на виріз, щоб розбудити компаньйона",
        onboardingRoleTitle: "Оберіть стартовий профіль",
        onboardingRoleDeveloper: "Розробник",
        onboardingRoleCreator: "Креатор",
        onboardingRoleMinimalist: "Мінімаліст",
        onboardingRolePower: "Усе разом",
        onboardingTryIsland: "Перевірити острів",
        onboardingTryCommandBar: "Перевірити панель",
        onboardingTryShelf: "Перевірити полицю",
        audioChainTitle: "Ланцюжок AUv3",
        audioChainSlotLabel: "Слот",
        perAppOutputTitle: "Вихід звуку",
        systemDefaultOutput: "Системний вихід",
        autoEQTitle: "Профіль навушників AutoEQ",
        autoEQImportButton: "Імпорт AutoEQ .txt…",
        loudnessToggleTitle: "Тонкомпенсація Loudness",
        hidpiMirrorTitle: "HiDPI-дзеркало монітора",
        hidpiMirrorConfirmBanner: "Залишити режим HiDPI? Автоматичний відкат…",
        hidpiMirrorConfirmAction: "Залишити",
        hidpiMirrorRevertAction: "Відкотити",
        solarSyncToggleTitle: "Сонячна крива яскравості",
        ddcStandbyAction: "Приспати екран (DDC)",
        xdrPerAppRulesTitle: "Авто-XDR для активних програм",
        menuBarManagerToggle: "Менеджер іконок меню-бара",
        menuBarOverflowTitle: "Приховані іконки меню-бара",
        wattsPackageLabel: "Потужність W",
        smartHealthTitle: "Стан NVMe S.M.A.R.T.",
        telemetrySevenDayHorizon: "7д",
        recorderCameraShapeTitle: "Форма камери",
        recorderPersonBlurToggle: "Розмиття фону портрета",
        recorderTilt3DToggle: "3D-нахил за курсором",
        recorderAspectTitle: "Формат кадру",
        recorderMicDuckingToggle: "Авто-приглушення при мові",
        screenshotSocialFramesTitle: "Пресет кадру",
        screenshotSmartGuidesToggle: "Магнітні напрямні",
        screenshotCloudHistoryTitle: "Історія хмари",
        screenshotCloudDeleteAction: "Видалити з хмари",
        clipboardFTSBadgeFormat: "FTS5 · %d шт.",
        clipboardLiveSyncToggle: "Жива синхронізація iCloud Vault",
        aiNewThreadButton: "Новий чат",
        aiAttachImageButton: "Додати зображення з буфера",
        inlineAITitle: "ШІ над виділеним",
        snippetsImportPackButton: "Імпорт / експорт набору…",
        spaceLensSunburstMode: "Сонце",
        spaceLensTreemapMode: "Плитки",
        spaceLensCollectTitle: "Кошик Collect",
        spaceLensCollectTrashAll: "Видалити зібране",
        startupAgentsTitle: "Автозапуск",
        duplicatesFinderTitle: "Дублікати",
        clopExternalToolsBadge: "CLI-кодеки Clop"
    )

    static let zhHans = OverhaulV3Strings(
        panelDensityCalm: "简洁",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "将指针移到刘海处唤醒伙伴",
        onboardingRoleTitle: "选择初始配置",
        onboardingRoleDeveloper: "开发者",
        onboardingRoleCreator: "创作者",
        onboardingRoleMinimalist: "极简",
        onboardingRolePower: "全功能",
        onboardingTryIsland: "体验灵动岛",
        onboardingTryCommandBar: "体验命令栏",
        onboardingTryShelf: "体验暂存架",
        audioChainTitle: "AUv3 效果链",
        audioChainSlotLabel: "插槽",
        perAppOutputTitle: "输出设备",
        systemDefaultOutput: "系统默认",
        autoEQTitle: "AutoEQ 耳机曲线",
        autoEQImportButton: "导入 AutoEQ .txt…",
        loudnessToggleTitle: "等响度补偿",
        hidpiMirrorTitle: "HiDPI 虚拟镜像",
        hidpiMirrorConfirmBanner: "保留此 HiDPI 模式吗？即将自动恢复…",
        hidpiMirrorConfirmAction: "保留",
        hidpiMirrorRevertAction: "立即恢复",
        solarSyncToggleTitle: "日照亮度曲线",
        ddcStandbyAction: "显示器休眠 (DDC)",
        xdrPerAppRulesTitle: "前台应用自动 XDR",
        menuBarManagerToggle: "菜单栏图标管理",
        menuBarOverflowTitle: "隐藏的菜单栏图标",
        wattsPackageLabel: "整机功耗 W",
        smartHealthTitle: "NVMe S.M.A.R.T. 健康度",
        telemetrySevenDayHorizon: "7天",
        recorderCameraShapeTitle: "摄像头造型",
        recorderPersonBlurToggle: "人像背景虚化",
        recorderTilt3DToggle: "3D 光标透视",
        recorderAspectTitle: "输出画幅",
        recorderMicDuckingToggle: "说话时自动闪避背景音",
        screenshotSocialFramesTitle: "画布比例预设",
        screenshotSmartGuidesToggle: "智能吸附参考线",
        screenshotCloudHistoryTitle: "云端上传记录",
        screenshotCloudDeleteAction: "从云端删除",
        clipboardFTSBadgeFormat: "FTS5 · %d 条",
        clipboardLiveSyncToggle: "iCloud Vault 实时同步",
        aiNewThreadButton: "新建对话",
        aiAttachImageButton: "附加剪贴板图片",
        inlineAITitle: "划词 AI 处理",
        snippetsImportPackButton: "导入 / 导出片段包…",
        spaceLensSunburstMode: "旭日图",
        spaceLensTreemapMode: "矩形树图",
        spaceLensCollectTitle: "Collect 收集篮",
        spaceLensCollectTrashAll: "移入废纸篓",
        startupAgentsTitle: "启动项管理",
        duplicatesFinderTitle: "重复文件",
        clopExternalToolsBadge: "Clop CLI 编码器"
    )

    static let zhTW = OverhaulV3Strings(
        panelDensityCalm: "簡潔",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "將指標移至瀏海處喚醒夥伴",
        onboardingRoleTitle: "選擇起始設定",
        onboardingRoleDeveloper: "開發者",
        onboardingRoleCreator: "創作者",
        onboardingRoleMinimalist: "極簡",
        onboardingRolePower: "完整套件",
        onboardingTryIsland: "體驗動態島",
        onboardingTryCommandBar: "體驗命令列",
        onboardingTryShelf: "體驗暫存架",
        audioChainTitle: "AUv3 效果鏈",
        audioChainSlotLabel: "插槽",
        perAppOutputTitle: "輸出裝置",
        systemDefaultOutput: "系統預設",
        autoEQTitle: "AutoEQ 耳機設定檔",
        autoEQImportButton: "匯入 AutoEQ .txt…",
        loudnessToggleTitle: "等響度補償",
        hidpiMirrorTitle: "HiDPI 虛擬鏡像",
        hidpiMirrorConfirmBanner: "保留此 HiDPI 模式嗎？即將自動還原…",
        hidpiMirrorConfirmAction: "保留",
        hidpiMirrorRevertAction: "立即還原",
        solarSyncToggleTitle: "日照亮度曲線",
        ddcStandbyAction: "顯示器待機 (DDC)",
        xdrPerAppRulesTitle: "前景 App 自動 XDR",
        menuBarManagerToggle: "選單列圖示管理",
        menuBarOverflowTitle: "隱藏的選單列圖示",
        wattsPackageLabel: "封裝功耗 W",
        smartHealthTitle: "NVMe S.M.A.R.T. 健康狀態",
        telemetrySevenDayHorizon: "7天",
        recorderCameraShapeTitle: "攝影機外框",
        recorderPersonBlurToggle: "人像背景模糊",
        recorderTilt3DToggle: "3D 游標透視",
        recorderAspectTitle: "輸出長寬比",
        recorderMicDuckingToggle: "說話時自動降低系統音量",
        screenshotSocialFramesTitle: "畫布比例預設",
        screenshotSmartGuidesToggle: "智慧對齊輔助線",
        screenshotCloudHistoryTitle: "雲端上傳紀錄",
        screenshotCloudDeleteAction: "從雲端刪除",
        clipboardFTSBadgeFormat: "FTS5 · %d 筆",
        clipboardLiveSyncToggle: "iCloud Vault 即時同步",
        aiNewThreadButton: "新對話",
        aiAttachImageButton: "附加剪貼簿圖片",
        inlineAITitle: "選取文字 AI",
        snippetsImportPackButton: "匯入 / 匯出套件…",
        spaceLensSunburstMode: "放射環圖",
        spaceLensTreemapMode: "矩形式樹圖",
        spaceLensCollectTitle: "Collect 收集籃",
        spaceLensCollectTrashAll: "丟到垃圾桶",
        startupAgentsTitle: "開機啟動項目",
        duplicatesFinderTitle: "重複檔案",
        clopExternalToolsBadge: "Clop CLI 編碼器"
    )

    static let zhHK = OverhaulV3Strings(
        panelDensityCalm: "簡潔",
        panelDensityPro: "Pro",
        onboardingMascotGreeting: "將指標移到劉海位置喚醒夥伴",
        onboardingRoleTitle: "揀選起始設定",
        onboardingRoleDeveloper: "開發者",
        onboardingRoleCreator: "創作者",
        onboardingRoleMinimalist: "極簡",
        onboardingRolePower: "全套功能",
        onboardingTryIsland: "試用動態島",
        onboardingTryCommandBar: "試用指令列",
        onboardingTryShelf: "試用暫存架",
        audioChainTitle: "AUv3 效果鏈",
        audioChainSlotLabel: "插槽",
        perAppOutputTitle: "輸出裝置",
        systemDefaultOutput: "系統預設",
        autoEQTitle: "AutoEQ 耳機設定檔",
        autoEQImportButton: "匯入 AutoEQ .txt…",
        loudnessToggleTitle: "等響度補償",
        hidpiMirrorTitle: "HiDPI 虛擬鏡像",
        hidpiMirrorConfirmBanner: "保留此 HiDPI 模式？即將自動還原…",
        hidpiMirrorConfirmAction: "保留",
        hidpiMirrorRevertAction: "立即還原",
        solarSyncToggleTitle: "日照亮度曲線",
        ddcStandbyAction: "顯示器待機 (DDC)",
        xdrPerAppRulesTitle: "前景 App 自動 XDR",
        menuBarManagerToggle: "選單列圖示管理",
        menuBarOverflowTitle: "隱藏選單列圖示",
        wattsPackageLabel: "功耗 W",
        smartHealthTitle: "NVMe S.M.A.R.T. 健康度",
        telemetrySevenDayHorizon: "7日",
        recorderCameraShapeTitle: "鏡頭框架",
        recorderPersonBlurToggle: "人像背景模糊",
        recorderTilt3DToggle: "3D 游標透視",
        recorderAspectTitle: "輸出比例",
        recorderMicDuckingToggle: "講嘢時自動壓低系統聲",
        screenshotSocialFramesTitle: "畫布比例預設",
        screenshotSmartGuidesToggle: "智能對齊輔助線",
        screenshotCloudHistoryTitle: "雲端上載記錄",
        screenshotCloudDeleteAction: "由雲端刪除",
        clipboardFTSBadgeFormat: "FTS5 · %d 項",
        clipboardLiveSyncToggle: "iCloud Vault 即時同步",
        aiNewThreadButton: "新對話",
        aiAttachImageButton: "附加剪貼簿圖片",
        inlineAITitle: "選取文字 AI",
        snippetsImportPackButton: "匯入 / 匯出套裝…",
        spaceLensSunburstMode: "環狀圖",
        spaceLensTreemapMode: "矩陣樹圖",
        spaceLensCollectTitle: "Collect 收集籃",
        spaceLensCollectTrashAll: "移至垃圾桶",
        startupAgentsTitle: "開機啟動項目",
        duplicatesFinderTitle: "重複檔案",
        clopExternalToolsBadge: "Clop CLI 編碼器"
    )
}

/// Clear attribution for this unofficial custom Intel Mac fork while keeping full credit and
/// donation links pointing directly to the original Vorssaint author (@vorssaint).
struct CustomForkAttribution {
    let badge: String
    let aboutSummary: String
    let donateCreditNote: String
    let originalRepoLabel: String
    let customForkRepoLabel: String

    static func localized(_ language: AppLanguage) -> CustomForkAttribution {
        switch language {
        case .ru:
            return CustomForkAttribution(
                badge: "Basalt · Intel Mac Fork",
                aboutSummary: "Basalt — независимая кастомная навайбкоженная альтернатива для Mac на процессорах Intel (x86_64) с собственным именем, иконкой и Bundle ID. Оригинальный Vorssaint работает только на Apple Silicon — Basalt создан на базе отличной работы автора @vorssaint.",
                donateCreditNote: "Ссылка на донат ведёт напрямую оригинальному автору Vorssaint (@vorssaint) — он проделал огромную работу, на которой основан Basalt.",
                originalRepoLabel: "Оригинальный Vorssaint",
                customForkRepoLabel: "Репозиторий Basalt"
            )
        case .uk:
            return CustomForkAttribution(
                badge: "Basalt · Intel Mac Fork",
                aboutSummary: "Basalt — незалежна кастомна навайбкоджена альтернатива для Mac на процесорах Intel (x86_64) із власним ім’ям, іконкою та Bundle ID. Оригінальний Vorssaint працює лише на Apple Silicon — Basalt створено на основі чудової роботи автора @vorssaint.",
                donateCreditNote: "Посилання на донат веде напряму до оригінального автора Vorssaint (@vorssaint), чия чудова робота лежить в основі Basalt.",
                originalRepoLabel: "Оригінальний Vorssaint",
                customForkRepoLabel: "Репозиторій Basalt"
            )
        case .de:
            return CustomForkAttribution(
                badge: "Custom Intel Mac Fork",
                aboutSummary: "Inoffizielle, per Vibe-Coding angepasste Alternative für Intel-Macs (x86_64). Das offizielle Vorssaint läuft nur auf Apple Silicon — dieser Fork baut auf der großartigen Arbeit von @vorssaint auf.",
                donateCreditNote: "Spenden über Buy Me a Coffee gehen direkt an den ursprünglichen Vorssaint-Autor (@vorssaint), auf dessen Arbeit dieser Intel-Fork basiert.",
                originalRepoLabel: "Original Vorssaint",
                customForkRepoLabel: "Intel-Fork"
            )
        case .fr:
            return CustomForkAttribution(
                badge: "Fork Custom · Intel Mac",
                aboutSummary: "Alternative personnalisée et non officielle (vibe-codée) pour Mac Intel (x86_64). L’application officielle Vorssaint ne fonctionne que sur Apple Silicon — ce fork repose sur l’excellent travail de @vorssaint.",
                donateCreditNote: "Le lien de don soutient directement l’auteur original de Vorssaint (@vorssaint), dont l’excellent travail est à la base de cette version Intel.",
                originalRepoLabel: "Vorssaint original",
                customForkRepoLabel: "Fork Intel"
            )
        case .es:
            return CustomForkAttribution(
                badge: "Fork Personalizado · Intel Mac",
                aboutSummary: "Alternativa personalizada no oficial (vibe-coded) para Mac con Intel (x86_64). El Vorssaint oficial solo funciona en Apple Silicon; este fork se basa en el gran trabajo de @vorssaint.",
                donateCreditNote: "Las donaciones van directamente al autor original de Vorssaint (@vorssaint), cuyo excelente trabajo hace posible esta versión para Intel.",
                originalRepoLabel: "Vorssaint original",
                customForkRepoLabel: "Fork Intel"
            )
        case .ptBR:
            return CustomForkAttribution(
                badge: "Fork Custom · Intel Mac",
                aboutSummary: "Alternativa personalizada não oficial (vibe-coded) para Macs Intel (x86_64). O Vorssaint oficial funciona apenas no Apple Silicon — este fork é baseado no ótimo trabalho de @vorssaint.",
                donateCreditNote: "As doações vão diretamente para o autor original do Vorssaint (@vorssaint), cujo excelente trabalho serve de base para esta edição Intel.",
                originalRepoLabel: "Vorssaint original",
                customForkRepoLabel: "Fork Intel"
            )
        case .it:
            return CustomForkAttribution(
                badge: "Fork Custom · Intel Mac",
                aboutSummary: "Alternativa personalizzata non ufficiale (vibe-coded) per Mac Intel (x86_64). Vorssaint ufficiale funziona solo su Apple Silicon: questo fork nasce sull’ottimo lavoro di @vorssaint.",
                donateCreditNote: "Le donazioni vanno direttamente all’autore originale di Vorssaint (@vorssaint), il cui ottimo lavoro è alla base di questa versione Intel.",
                originalRepoLabel: "Vorssaint originale",
                customForkRepoLabel: "Fork Intel"
            )
        case .tr:
            return CustomForkAttribution(
                badge: "Özel Intel Mac Çatalı",
                aboutSummary: "Intel Mac (x86_64) için resmi olmayan, vibe-coded özel alternatif. Orijinal Vorssaint yalnızca Apple Silicon’da çalışır; bu sürüm @vorssaint’in harika çalışması üzerine kuruludur.",
                donateCreditNote: "Bağış bağlantısı doğrudan bu özel Intel sürümünün temelini oluşturan orijinal Vorssaint yazarına (@vorssaint) gider.",
                originalRepoLabel: "Orijinal Vorssaint",
                customForkRepoLabel: "Intel Çatalı"
            )
        case .sk:
            return CustomForkAttribution(
                badge: "Vlastný Intel Mac Fork",
                aboutSummary: "Neoficiálna vlastná (vibe-coded) alternatíva pre Intel Mac (x86_64). Oficiálny Vorssaint funguje iba na Apple Silicon — tento fork stavia na skvelej práci autora @vorssaint.",
                donateCreditNote: "Odkaz na podporu smeruje priamo k pôvodnému autorovi Vorssaint (@vorssaint), na ktorého skvelej práci táto Intel verzia stojí.",
                originalRepoLabel: "Pôvodný Vorssaint",
                customForkRepoLabel: "Intel fork"
            )
        case .ja:
            return CustomForkAttribution(
                badge: "カスタム Intel Mac 版",
                aboutSummary: "Intel Mac (x86_64) 向けの非公式カスタム（バイブコーディング）フォークです。公式 Vorssaint は Apple Silicon 専用のため、@vorssaint の素晴らしい開発成果をもとに Intel 向けに拡張しています。",
                donateCreditNote: "寄付リンクはオリジナルの Vorssaint 開発者（@vorssaint）へ直接届きます。このカスタム Intel 版は同氏の素晴らしい仕事に基づいています。",
                originalRepoLabel: "公式 Vorssaint",
                customForkRepoLabel: "Intel フォーク"
            )
        case .ko:
            return CustomForkAttribution(
                badge: "커스텀 Intel Mac 포크",
                aboutSummary: "Intel Mac(x86_64)을 위한 비공식 커스텀(바이브 코딩) 대안 버전입니다. 공식 Vorssaint는 Apple Silicon 전용이므로 @vorssaint의 훌륭한 원작을 바탕으로 Intel용으로 제작되었습니다.",
                donateCreditNote: "후원 링크는 이 커스텀 Intel 버전의 기반이 된 원작자(@vorssaint)에게 직접 전달됩니다.",
                originalRepoLabel: "원본 Vorssaint",
                customForkRepoLabel: "Intel 포크"
            )
        case .zhHans:
            return CustomForkAttribution(
                badge: "定制版 · Intel Mac",
                aboutSummary: "面向 Intel Mac (x86_64) 的非官方定制（vibe-coded）替代版本。官方 Vorssaint 仅支持 Apple Silicon，本分支基于原作者 @vorssaint 的出色作品构建。",
                donateCreditNote: "赞助链接直接指向 Vorssaint 原作者（@vorssaint）——感谢他打造了如此优秀的基础项目。",
                originalRepoLabel: "原版 Vorssaint",
                customForkRepoLabel: "Intel 定制分支"
            )
        case .zhTW, .zhHK:
            return CustomForkAttribution(
                badge: "客製版 · Intel Mac",
                aboutSummary: "專為 Intel Mac (x86_64) 打造的非官方客製（vibe-coded）替代版本。官方 Vorssaint 僅支援 Apple Silicon，本分支基於原作者 @vorssaint 的優秀作品延伸。",
                donateCreditNote: "贊助連結直接導向 Vorssaint 原作者（@vorssaint）——感謝他奠定了如此出色的基礎。",
                originalRepoLabel: "原版 Vorssaint",
                customForkRepoLabel: "Intel 客製分支"
            )
        case .enUS:
            return CustomForkAttribution(
                badge: "Basalt · Intel Mac Fork",
                aboutSummary: "Basalt is an independent, custom vibe-coded alternative for Intel Macs (x86_64) with its own name, icon, and bundle ID. Official Vorssaint runs on Apple Silicon only — Basalt builds on @vorssaint’s great work.",
                donateCreditNote: "Donations go directly to the original Vorssaint author (@vorssaint), whose great work Basalt is built on.",
                originalRepoLabel: "Original Vorssaint",
                customForkRepoLabel: "Basalt Fork"
            )
        }
    }
}
