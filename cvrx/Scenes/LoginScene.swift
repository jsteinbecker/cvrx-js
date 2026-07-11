import SwiftUI

struct LoginScene: View {
    let store: CompoundingStore
    let supabaseAuth: SupabaseAuthService?
    let onLogin: (User) -> Void

    @AppStorage("login.rememberMe") private var rememberMe = false
    @AppStorage("login.rememberedUsername") private var rememberedUsername = ""
    @AppStorage("login.rememberedFacilityID") private var rememberedFacilityID = ""

    @State private var username = ""
    @State private var password = ""
    @State private var facilityID = ""
    @State private var showLoginError = false
    @State private var loginErrorMessage = "Username, password, or facility ID is incorrect."
    @State private var isAuthenticating = false
    @FocusState private var focusedField: LoginField?

    private enum LoginField {
        case username
        case password
        case facilityID
    }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.tint)

                    Text("CVRx")
                        .font(.largeTitle.weight(.semibold))

                    Text("Compounding documentation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    TextField(supabaseAuth == nil ? "Username" : "Email", text: $username)
                        .autocorrectionDisabled()
                        .textContentType(supabaseAuth == nil ? .username : .emailAddress)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .username)
                        .onSubmit { focusedField = .password }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .password)
                        .onSubmit { focusedField = .facilityID }

                    TextField("Facility ID", text: $facilityID)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focusedField, equals: .facilityID)
                        .onSubmit(authenticate)

                    Toggle("Remember me", isOn: $rememberMe)
                        .font(.subheadline)
#if os(iOS)
                        .toggleStyle(.switch)
#else
                        .toggleStyle(.checkbox)
#endif
                }
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

                if showLoginError {
                    Label(loginErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: 360, alignment: .leading)
                }

                Button(action: authenticate) {
                    Label(isAuthenticating ? "Logging In" : "Log In", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: 360)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canSubmit || isAuthenticating)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .disabled(isAuthenticating)

            if isAuthenticating {
                authenticatingOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAuthenticating)
        .onAppear(perform: prepareLoginForm)
        .onChange(of: username) { _, _ in showLoginError = false }
        .onChange(of: password) { _, _ in showLoginError = false }
        .onChange(of: facilityID) { _, _ in showLoginError = false }
        .onChange(of: rememberMe) { _, isRemembering in
            if !isRemembering {
                clearRememberedLogin()
            }
        }
    }

    private var authenticatingOverlay: some View {
        Rectangle()
            .fill(.background.opacity(0.86))
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 20) {
                    ProgressView()
                        .controlSize(.large)
                        .scaleEffect(2.2)

                    Text("Logging in")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(40)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Logging in")
    }

    private var canSubmit: Bool {
        !username.normalizedLoginValue.isEmpty
        && !password.isEmpty
        && !facilityID.normalizedLoginValue.isEmpty
    }

    private func prepareLoginForm() {
        if rememberMe {
            username = rememberedUsername
            facilityID = rememberedFacilityID
            focusedField = username.isEmpty ? .username : .password
        } else {
            focusedField = .username
        }
    }

    private func authenticate() {
        guard canSubmit, !isAuthenticating else { return }
        showLoginError = false

        if let supabaseAuth {
            isAuthenticating = true
            Task {
                do {
                    let user = try await supabaseAuth.authenticate(
                        username: username,
                        password: password,
                        facilityID: facilityID
                    )
                    await MainActor.run {
                        let localUser = store.upsertLocalUser(from: user)
                        updateRememberedLogin()
                        password = ""
                        isAuthenticating = false
                        onLogin(localUser)
                    }
                } catch {
                    await MainActor.run {
                        loginErrorMessage = error.localizedDescription
                        showLoginError = true
                        isAuthenticating = false
                    }
                }
            }
            return
        }

        guard let user = store.authenticateUser(
            username: username,
            password: password,
            facilityID: facilityID
        ) else {
            loginErrorMessage = "Username, password, or facility ID is incorrect."
            showLoginError = true
            return
        }

        updateRememberedLogin()
        password = ""
        onLogin(user)
    }

    private func updateRememberedLogin() {
        if rememberMe {
            rememberedUsername = username.normalizedLoginValue
            rememberedFacilityID = facilityID.normalizedLoginValue
        } else {
            clearRememberedLogin()
        }
    }

    private func clearRememberedLogin() {
        rememberedUsername = ""
        rememberedFacilityID = ""
    }
}
