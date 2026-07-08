import SwiftUI

struct LoginScene: View {
    let store: CompoundingStore
    let onLogin: (User) -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var facilityID = ""
    @State private var showLoginError = false
    @FocusState private var focusedField: LoginField?

    private enum LoginField {
        case username
        case password
        case facilityID
    }

    var body: some View {
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
                TextField("Username", text: $username)
                    .autocorrectionDisabled()
                    .textContentType(.username)
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
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 360)

            if showLoginError {
                Label("Username, password, or facility ID is incorrect.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 360, alignment: .leading)
            }

            Button(action: authenticate) {
                Label("Log In", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: 360)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .onAppear { focusedField = .username }
        .onChange(of: username) { _, _ in showLoginError = false }
        .onChange(of: password) { _, _ in showLoginError = false }
        .onChange(of: facilityID) { _, _ in showLoginError = false }
    }

    private var canSubmit: Bool {
        !username.normalizedLoginValue.isEmpty
        && !password.isEmpty
        && !facilityID.normalizedLoginValue.isEmpty
    }

    private func authenticate() {
        guard canSubmit else { return }
        guard let user = store.authenticateUser(
            username: username,
            password: password,
            facilityID: facilityID
        ) else {
            showLoginError = true
            return
        }

        password = ""
        onLogin(user)
    }
}
