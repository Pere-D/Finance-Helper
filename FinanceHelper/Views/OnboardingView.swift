import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    var onComplete: () -> Void

    @State private var page = 0
    private let totalPages = 5

    @AppStorage("default_currency") private var defaultCurrency = "EUR"
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @State private var selectedCurrency = ""

    // MARK: - Profile state (page 2)
    @State private var profileName = ""
    @State private var profileEmoji = "👤"
    @State private var onboardingProfileCreated = false

    // MARK: - Wizard state (page 4)
    // 0=income Q, 1=income amount, 2=income account,
    // 3=debt Q,   4=debt detail,
    // 5=goal Q,   6=goal category, 7=goal detail
    @State private var wizardStep = 0

    @State private var incomeAmount: Double? = nil
    @State private var incomeName = ""
    @State private var incomeType: AccountType = .girokonto
    @State private var incomeBalance: Double? = nil

    @State private var debtName = ""
    @State private var debtType: AccountType = .kredit
    @State private var debtAmount: Double? = nil

    @State private var goalCategory: GoalCategory = .custom
    @State private var goalName = ""
    @State private var goalAmount: Double? = nil

    // Unified focus state for all text inputs
    enum FocusedField: Hashable {
        case profileName
        case incomeAmount, incomeBalance, incomeName
        case debtAmount, debtName
        case goalAmount, goalName
    }
    @FocusState private var focusedField: FocusedField?

    private var isYNStep: Bool    { page == 4 && [0, 3, 5].contains(wizardStep) }
    private var isDetailStep: Bool { page == 4 && [1, 2, 4, 6, 7].contains(wizardStep) }

    private var detailCanProceed: Bool {
        switch wizardStep {
        case 1: return true
        case 2: return !incomeName.trimmingCharacters(in: .whitespaces).isEmpty
        case 4: return !debtName.trimmingCharacters(in: .whitespaces).isEmpty && (debtAmount ?? 0) > 0
        case 6: return true
        case 7: return !goalName.trimmingCharacters(in: .whitespaces).isEmpty && (goalAmount ?? 0) > 0
        default: return false
        }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            pageAccentColor.opacity(0.06).ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: page)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(NSLocalizedString("onboarding_skip", comment: "")) { finish() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .opacity(page < totalPages - 1 ? 1 : 0.5)
                        .animation(.easeInOut, value: page)
                }
                .frame(height: 50)
                .padding(.top, 50)

                TabView(selection: $page) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    profilePage.tag(2)
                    currencyPage.tag(3)
                    setupWizardPage.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { i in
                            Capsule()
                                .fill(i == page ? pageAccentColor : Color.secondary.opacity(0.25))
                                .frame(width: i == page ? 22 : 8, height: 8)
                                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: page)
                        }
                    }

                    if !isYNStep {
                        let locked = (isDetailStep && !detailCanProceed)
                            || (page == 2 && profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button {
                            triggerHaptic()
                            advance()
                        } label: {
                            HStack(spacing: 8) {
                                Text(nextLabel).font(.headline)
                                Image(systemName: locked ? "lock.fill" : nextIcon)
                                    .font(.subheadline.weight(.bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(locked ? Color.secondary.opacity(0.12) : pageAccentColor)
                            .foregroundStyle(locked ? Color.secondary : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: locked ? .clear : pageAccentColor.opacity(0.35), radius: 10, x: 0, y: 4)
                        }
                        .disabled(locked)
                        .padding(.horizontal, 24)
                        .animation(.easeInOut(duration: 0.18), value: locked)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.bottom, 44)
                .animation(.easeInOut(duration: 0.2), value: isYNStep)
            }
        }
        .onAppear {
            let detected = Locale.current.currency?.identifier ?? "EUR"
            selectedCurrency = currencyOptions.map(\.code).contains(detected) ? detected : "EUR"
        }
        .onChange(of: page) { _, newPage in
            if newPage == 2 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    focusedField = .profileName
                }
            }
            if newPage == 4 { wizardStep = 0 }
        }
    }

    // MARK: - Labels

    private var nextLabel: String {
        if page < 4 { return NSLocalizedString("onboarding_next", comment: "") }
        if wizardStep == 7 { return NSLocalizedString("onboarding_open_dashboard", comment: "") }
        return NSLocalizedString("onboarding_next", comment: "")
    }
    private var nextIcon: String { wizardStep == 7 && page == 4 ? "checkmark" : "arrow.right" }
    private var pageAccentColor: Color {
        switch page {
        case 0: return .green
        case 1: return .blue
        case 2: return .teal
        case 3: return .orange
        default: return .indigo
        }
    }

    // MARK: - Welcome Page

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color.green.opacity(0.18), Color.green.opacity(0.04)],
                                        center: .center, startRadius: 30, endRadius: 90))
                    .frame(width: 160, height: 160)
                Image("AppLogo")
                    .resizable().scaledToFit().frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
            }
            Spacer().frame(height: 32)
            VStack(spacing: 10) {
                Text(NSLocalizedString("onboarding_welcome_title", comment: ""))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(NSLocalizedString("onboarding_welcome_subtitle", comment: ""))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
            HStack(spacing: 0) {
                OnboardingChip(icon: "chart.pie.fill", label: "Dashboard",
                               sublabel: NSLocalizedString("onboarding_chip_overview", comment: ""), color: .blue)
                OnboardingChip(icon: "list.bullet.rectangle.portrait.fill", label: "Budget",
                               sublabel: NSLocalizedString("onboarding_chip_planning", comment: ""), color: .green)
                OnboardingChip(icon: "heart.text.clipboard.fill", label: "Score",
                               sublabel: NSLocalizedString("onboarding_chip_health", comment: ""), color: .red)
                OnboardingChip(icon: "chart.line.uptrend.xyaxis", label: "Prognose",
                               sublabel: NSLocalizedString("onboarding_chip_future", comment: ""), color: .orange)
            }
            .padding(.horizontal, 12)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Features Page

    private var featuresPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(NSLocalizedString("onboarding_features_title", comment: ""))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .padding(.bottom, 28)
                VStack(spacing: 20) {
                    OnboardingFeatureRow(icon: "creditcard.fill", color: .blue,
                                        title: NSLocalizedString("onboarding_feature1_title", comment: ""),
                                        desc: NSLocalizedString("onboarding_feature1_desc", comment: ""))
                    OnboardingFeatureRow(icon: "arrow.left.arrow.right", color: .green,
                                        title: NSLocalizedString("onboarding_feature2_title", comment: ""),
                                        desc: NSLocalizedString("onboarding_feature2_desc", comment: ""))
                    OnboardingFeatureRow(icon: "list.bullet.rectangle.portrait.fill", color: .orange,
                                        title: NSLocalizedString("onboarding_feature3_title", comment: ""),
                                        desc: NSLocalizedString("onboarding_feature3_desc", comment: ""))
                    OnboardingFeatureRow(icon: "chart.line.uptrend.xyaxis", color: .purple,
                                        title: NSLocalizedString("onboarding_feature4_title", comment: ""),
                                        desc: NSLocalizedString("onboarding_feature4_desc", comment: ""))
                    OnboardingFeatureRow(icon: "heart.text.clipboard.fill", color: .red,
                                        title: NSLocalizedString("onboarding_feature5_title", comment: ""),
                                        desc: NSLocalizedString("onboarding_feature5_desc", comment: ""))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Profile Page

    private var profilePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                // Avatar display
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.teal.opacity(0.12))
                            .frame(width: 92, height: 92)
                        Text(profileEmoji)
                            .font(.system(size: 48))
                    }
                    VStack(spacing: 6) {
                        Text(NSLocalizedString("onboarding_profile_title", comment: ""))
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text(NSLocalizedString("onboarding_profile_subtitle", comment: ""))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 12)

                // Name input
                TextField(NSLocalizedString("onboarding_profile_placeholder", comment: ""), text: $profileName)
                    .font(.body)
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(focusedField == .profileName
                                    ? Color.teal.opacity(0.45)
                                    : Color.clear,
                                    lineWidth: 1.5)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .focused($focusedField, equals: .profileName)
                    .onTapGesture { focusedField = .profileName }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)

                // Emoji picker
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("onboarding_profile_emoji_label", comment: ""))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                        ForEach(profileEmojis, id: \.self) { emoji in
                            Button { triggerHaptic(); profileEmoji = emoji } label: {
                                Text(emoji)
                                    .font(.system(size: 26))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(profileEmoji == emoji
                                        ? Color.teal.opacity(0.15)
                                        : Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(profileEmoji == emoji
                                                    ? Color.teal.opacity(0.4)
                                                    : Color.clear,
                                                    lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.12), value: profileEmoji)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Currency Page

    private var currencyPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("onboarding_currency_title", comment: ""))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(NSLocalizedString("onboarding_currency_subtitle", comment: ""))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 4),
                    spacing: 8
                ) {
                    ForEach(currencyOptions, id: \.code) { option in
                        Button { triggerHaptic(); selectedCurrency = option.code } label: {
                            VStack(spacing: 3) {
                                Text(option.flag).font(.system(size: 22))
                                Text(option.code)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(selectedCurrency == option.code ? .white : .primary)
                                Text(option.name)
                                    .font(.system(size: 9))
                                    .foregroundStyle(selectedCurrency == option.code ? .white.opacity(0.85) : .secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedCurrency == option.code ? Color.orange : Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: selectedCurrency)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.orange.opacity(0.8)).font(.caption).padding(.top, 1)
                    Text(NSLocalizedString("onboarding_currency_disclaimer", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
    }

    private var currencyOptions: [CurrencyOption] {[
        CurrencyOption(code: "EUR", name: "Euro",       flag: "🇪🇺"),
        CurrencyOption(code: "CHF", name: "Franken",    flag: "🇨🇭"),
        CurrencyOption(code: "USD", name: "US Dollar",  flag: "🇺🇸"),
        CurrencyOption(code: "GBP", name: "Pound",      flag: "🇬🇧"),
        CurrencyOption(code: "JPY", name: "Yen",        flag: "🇯🇵"),
        CurrencyOption(code: "CAD", name: "CA Dollar",  flag: "🇨🇦"),
        CurrencyOption(code: "AUD", name: "AU Dollar",  flag: "🇦🇺"),
        CurrencyOption(code: "SEK", name: "Krona",      flag: "🇸🇪"),
        CurrencyOption(code: "NOK", name: "Krone",      flag: "🇳🇴"),
        CurrencyOption(code: "DKK", name: "DK Krone",   flag: "🇩🇰"),
        CurrencyOption(code: "CZK", name: "Koruna",     flag: "🇨🇿"),
        CurrencyOption(code: "PLN", name: "Zloty",      flag: "🇵🇱"),
        CurrencyOption(code: "HUF", name: "Forint",     flag: "🇭🇺"),
        CurrencyOption(code: "RON", name: "Leu",        flag: "🇷🇴"),
        CurrencyOption(code: "HKD", name: "HK Dollar",  flag: "🇭🇰"),
        CurrencyOption(code: "SGD", name: "SG Dollar",  flag: "🇸🇬"),
        CurrencyOption(code: "CNY", name: "Renminbi",   flag: "🇨🇳"),
        CurrencyOption(code: "INR", name: "Rupee",      flag: "🇮🇳"),
        CurrencyOption(code: "BRL", name: "Real",       flag: "🇧🇷"),
        CurrencyOption(code: "TRY", name: "Lira",       flag: "🇹🇷"),
        CurrencyOption(code: "AED", name: "Dirham",     flag: "🇦🇪"),
        CurrencyOption(code: "SAR", name: "Riyal",      flag: "🇸🇦"),
        CurrencyOption(code: "KRW", name: "Won",        flag: "🇰🇷"),
        CurrencyOption(code: "MXN", name: "Peso",       flag: "🇲🇽"),
    ]}

    // MARK: - Setup Wizard Page

    @ViewBuilder
    private var setupWizardPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                wizardTopicDot(icon: "banknote.fill", color: .green,
                               active: wizardStep >= 0, done: wizardStep >= 3)
                wizardConnector(filled: wizardStep >= 3)
                wizardTopicDot(icon: "arrow.counterclockwise.circle.fill", color: .red,
                               active: wizardStep >= 3, done: wizardStep >= 5)
                wizardConnector(filled: wizardStep >= 5)
                wizardTopicDot(icon: "target", color: .teal,
                               active: wizardStep >= 5, done: false)
            }
            .padding(.horizontal, 48)
            .padding(.top, 16)
            .padding(.bottom, 4)

            wizardStepContent
                .id(wizardStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: wizardStep)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var wizardStepContent: some View {
        switch wizardStep {
        case 0:
            wizardQuestionView(
                icon: "banknote.fill", iconColor: .green,
                title: NSLocalizedString("wizard_income_question", comment: ""),
                subtitle: NSLocalizedString("wizard_income_subtitle", comment: ""),
                onYes: { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { wizardStep = 1 } },
                onNo:  { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { wizardStep = 3 } }
            )
        case 1:
            wizardIncomeAmount
        case 2:
            wizardIncomeAccount
        case 3:
            wizardQuestionView(
                icon: "arrow.counterclockwise.circle.fill", iconColor: .red,
                title: NSLocalizedString("wizard_debt_question", comment: ""),
                subtitle: NSLocalizedString("wizard_debt_subtitle", comment: ""),
                onYes: { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { wizardStep = 4 } },
                onNo:  { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { wizardStep = 5 } }
            )
        case 4:
            wizardDebtDetail
        case 5:
            wizardQuestionView(
                icon: "target", iconColor: .teal,
                title: NSLocalizedString("wizard_goal_question", comment: ""),
                subtitle: NSLocalizedString("wizard_goal_subtitle", comment: ""),
                onYes: { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { wizardStep = 6 } },
                onNo:  { finish() }
            )
        case 6:
            wizardGoalCategory
        case 7:
            wizardGoalDetail
        default:
            EmptyView()
        }
    }

    // MARK: - Topic Indicator Helpers

    private func wizardTopicDot(icon: String, color: Color, active: Bool, done: Bool) -> some View {
        ZStack {
            Circle()
                .fill(active ? color.opacity(0.15) : Color.secondary.opacity(0.08))
                .frame(width: 40, height: 40)
            if done {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(color)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(active ? color : Color.secondary.opacity(0.35))
            }
        }
    }

    private func wizardConnector(filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.15))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 1)
    }

    // MARK: - Y/N Question Template

    private func wizardQuestionView(
        icon: String, iconColor: Color,
        title: String, subtitle: String,
        onYes: @escaping () -> Void,
        onNo: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(iconColor.opacity(0.12)).frame(width: 100, height: 100)
                Image(systemName: icon).font(.system(size: 44, weight: .medium)).foregroundStyle(iconColor)
            }
            Spacer().frame(height: 28)
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            Spacer().frame(height: 36)
            VStack(spacing: 12) {
                Button {
                    triggerHaptic()
                    onYes()
                } label: {
                    Text(NSLocalizedString("wizard_yes", comment: ""))
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(iconColor).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: iconColor.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                Button {
                    triggerHaptic()
                    onNo()
                } label: {
                    Text(NSLocalizedString("wizard_no_skip", comment: ""))
                        .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.secondary.opacity(0.1)).foregroundStyle(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Income Amount (step 1)

    private var wizardIncomeAmount: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.green.opacity(0.12)).frame(width: 68, height: 68)
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    VStack(spacing: 4) {
                        Text(NSLocalizedString("wizard_income_how_much", comment: ""))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text(NSLocalizedString("wizard_income_per_month", comment: ""))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)

                // Amount box — compact, right-aligned, whole box tappable
                HStack(spacing: 10) {
                    Text(effectiveCurrency)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.green.opacity(0.65))
                    TextField("0", value: $incomeAmount, format: .number)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .incomeAmount)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20).padding(.vertical, 18)
                .background(Color.green.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(focusedField == .incomeAmount
                                ? Color.green.opacity(0.45)
                                : Color.green.opacity(0.22),
                                lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .incomeAmount }
                .animation(.easeInOut(duration: 0.15), value: focusedField == .incomeAmount)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Income Account (step 2)

    private var wizardIncomeAccount: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("wizard_income_account_title", comment: ""))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(NSLocalizedString("wizard_income_account_subtitle", comment: ""))
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                // Account type grid (non-liability types only)
                let incomeTypes = AccountType.allCases.filter { !$0.isLiability }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(incomeTypes, id: \.self) { t in
                        Button { triggerHaptic(); incomeType = t } label: {
                            HStack(spacing: 10) {
                                Image(systemName: t.systemImage)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(incomeType == t ? .white : t.typeColor)
                                    .frame(width: 20)
                                Text(t.localizedName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(incomeType == t ? .white : .primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 14)
                            .background(incomeType == t ? t.typeColor : Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: incomeType)
                    }
                }

                // Account name — full field tappable
                TextField(NSLocalizedString("wizard_income_account_placeholder", comment: ""), text: $incomeName)
                    .font(.body)
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .focused($focusedField, equals: .incomeName)
                    .onTapGesture { focusedField = .incomeName }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)

                // Current balance — right-aligned, whole box tappable
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("wizard_income_balance_label", comment: ""))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    amountInputBox(
                        value: $incomeBalance,
                        field: .incomeBalance,
                        accentColor: .green
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Debt Detail (step 4)

    private var wizardDebtDetail: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("wizard_debt_account_title", comment: ""))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(NSLocalizedString("wizard_debt_account_subtitle", comment: ""))
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                // Debt type grid (liability types only)
                let debtTypes = AccountType.allCases.filter(\.isLiability)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(debtTypes, id: \.self) { t in
                        Button { triggerHaptic(); debtType = t } label: {
                            HStack(spacing: 10) {
                                Image(systemName: t.systemImage)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(debtType == t ? .white : t.typeColor)
                                    .frame(width: 20)
                                Text(t.localizedName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(debtType == t ? .white : .primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 14)
                            .background(debtType == t ? t.typeColor : Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: debtType)
                    }
                }

                // Debt name — full field tappable
                TextField(NSLocalizedString("wizard_debt_account_placeholder", comment: ""), text: $debtName)
                    .font(.body)
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .focused($focusedField, equals: .debtName)
                    .onTapGesture { focusedField = .debtName }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)

                // Outstanding balance
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("wizard_debt_amount_label", comment: ""))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    amountInputBox(
                        value: $debtAmount,
                        field: .debtAmount,
                        accentColor: .red
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Goal Category Picker (step 6)

    private var wizardGoalCategory: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("wizard_goal_category_title", comment: ""))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(NSLocalizedString("wizard_goal_category_subtitle", comment: ""))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    ForEach(GoalCategory.allCases) { cat in
                        Button { triggerHaptic(); goalCategory = cat } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(goalCategory == cat ? cat.color : cat.color.opacity(0.12))
                                        .frame(width: 52, height: 52)
                                    Image(systemName: cat.systemImage)
                                        .font(.system(size: 22, weight: .medium))
                                        .foregroundStyle(goalCategory == cat ? .white : cat.color)
                                }
                                Text(cat.localizedName)
                                    .font(.caption2.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundStyle(goalCategory == cat ? cat.color : .primary)
                            }
                            .padding(.vertical, 14).padding(.horizontal, 4)
                            .frame(maxWidth: .infinity)
                            .background(goalCategory == cat ? cat.color.opacity(0.10) : Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(goalCategory == cat ? cat.color.opacity(0.35) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: goalCategory)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Goal Detail (step 7)

    private var wizardGoalDetail: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Category badge
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(goalCategory.color.opacity(0.15)).frame(width: 56, height: 56)
                        Image(systemName: goalCategory.systemImage)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(goalCategory.color)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(goalCategory.localizedName).font(.headline)
                        Text(goalCategory.fullDescription).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(goalCategory.color.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Goal name — full field tappable
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("wizard_goal_name_label", comment: ""))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField(goalCategory.localizedName, text: $goalName)
                        .font(.body)
                        .padding(16)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                        .focused($focusedField, equals: .goalName)
                        .onTapGesture { focusedField = .goalName }
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                }

                // Goal amount with suggested presets
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("wizard_goal_amount_label", comment: ""))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(goalCategory.suggestedAmounts, id: \.self) { amt in
                                Button {
                                    triggerHaptic()
                                    goalAmount = amt
                                } label: {
                                    Text(amt.formatted(.currency(code: effectiveCurrency).precision(.fractionLength(0))))
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .background(goalAmount == Optional(amt)
                                            ? goalCategory.color.opacity(0.18)
                                            : Color.secondary.opacity(0.10))
                                        .foregroundStyle(goalAmount == Optional(amt)
                                            ? goalCategory.color
                                            : .secondary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    amountInputBox(
                        value: $goalAmount,
                        field: .goalAmount,
                        accentColor: goalCategory.color
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Shared Amount Input Box

    private func amountInputBox(value: Binding<Double?>, field: FocusedField, accentColor: Color) -> some View {
        HStack(spacing: 12) {
            Text(effectiveCurrency)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("0", value: value, format: .number)
                .font(.title2.weight(.bold))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: field)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
        .background(Color(.systemGray6))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(focusedField == field ? accentColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
        .animation(.easeInOut(duration: 0.12), value: focusedField == field)
    }

    // MARK: - Navigation

    private func advance() {
        if page < totalPages - 1 {
            if page == 2 {
                // Profile page confirmed — create profile now so activeProfileID is ready
                // before any accounts are created in the wizard
                ensureProfileCreated()
            }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { page += 1 }
            return
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            switch wizardStep {
            case 1: wizardStep = 2
            case 2: createIncomeAccount(); wizardStep = 3
            case 4: createDebtAccount();   wizardStep = 5
            case 6:
                wizardStep = 7
            case 7: createGoal(); finish()
            default: break
            }
        }
    }

    // MARK: - Entity Creation

    private var effectiveCurrency: String {
        selectedCurrency.isEmpty ? defaultCurrency : selectedCurrency
    }

    private func ensureProfileCreated() {
        guard !onboardingProfileCreated else { return }
        onboardingProfileCreated = true
        createProfile()
    }

    private func createProfile() {
        let name = profileName.trimmingCharacters(in: .whitespaces)
        let profile = UserProfile(
            name: name.isEmpty ? NSLocalizedString("default_profile_name", comment: "") : name,
            emoji: profileEmoji
        )
        modelContext.insert(profile)
        activeProfileID = profile.id.uuidString
    }

    private func createIncomeAccount() {
        let account = Account(
            name: incomeName.trimmingCharacters(in: .whitespaces),
            type: incomeType,
            balance: incomeBalance ?? 0,
            currency: effectiveCurrency
        )
        account.profileID = activeProfileID
        modelContext.insert(account)
        if let amt = incomeAmount, amt > 0 {
            let entry = BudgetEntry(category: .haupteinkommen, amount: amt,
                                    recurrence: .monthly, dueDay: 25)
            entry.account = account
            entry.profileID = activeProfileID
            modelContext.insert(entry)
        }
    }

    private func createDebtAccount() {
        let account = Account(
            name: debtName.trimmingCharacters(in: .whitespaces),
            type: debtType,
            balance: debtAmount ?? 0,
            currency: effectiveCurrency
        )
        account.profileID = activeProfileID
        modelContext.insert(account)
    }

    private func createGoal() {
        let goal = FinancialGoal(
            profileID: activeProfileID,
            name: goalName.trimmingCharacters(in: .whitespaces),
            category: goalCategory,
            targetAmount: goalAmount ?? 0,
            currency: effectiveCurrency
        )
        modelContext.insert(goal)
    }

    private func finish() {
        if !selectedCurrency.isEmpty { defaultCurrency = selectedCurrency }
        // Fallback: create profile if user skipped before reaching the profile page
        if !onboardingProfileCreated { createProfile() }
        withAnimation(.easeOut(duration: 0.35)) { onComplete() }
    }

    private func triggerHaptic() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Models

private struct CurrencyOption {
    let code: String
    let name: String
    let flag: String
}

// MARK: - Helper Views

private struct OnboardingChip: View {
    let icon: String
    let label: String
    let sublabel: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(color)
                )
            VStack(spacing: 1) {
                Text(label).font(.caption.weight(.semibold))
                Text(sublabel).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 13)
                .fill(color.opacity(0.12))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(color)
                )
                .shadow(color: color.opacity(0.15), radius: 6, x: 0, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(desc).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .modelContainer(for: [Account.self, MonthlyEntry.self, BudgetEntry.self, FinancialGoal.self, UserProfile.self], inMemory: true)
}
