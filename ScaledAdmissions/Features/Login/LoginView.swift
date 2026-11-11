import SwiftUI

/// Care Assist's sign-in, in Scaled blue.
struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var touchLocation: CGPoint?

    var body: some View {
        ZStack {
            AnimatedBackgroundView(touchLocation: $touchLocation)

            VStack {
                Spacer(minLength: 60)

                // MARK: - Title
                VStack(spacing: 14) {
                    Image("ScaledMark")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(Theme.accentText)
                        .frame(height: 84)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 5)

                    Text("Scaled Admissions")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ink)

                    Text("Never lose another lead.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink.opacity(0.6))
                }

                Spacer().frame(height: 40)

                // MARK: - Card
                VStack(spacing: 20) {
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundStyle(.gray)
                        TextField("Email", text: $email)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                    }
                    .padding()
                    .background(Theme.chipFlat)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    HStack {
                        Image(systemName: "lock")
                            .foregroundStyle(.gray)
                        if isPasswordVisible {
                            TextField("Password", text: $password)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } else {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                        }
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(.gray)
                        }
                    }
                    .padding()
                    .background(Theme.chipFlat)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .onSubmit(signIn)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.badText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: signIn) {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Sign In").bold()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.white)
                        .background(Theme.accentText)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Theme.accent.opacity(0.3), radius: 8, y: 6)
                    }
                    .disabled(isLoading)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.05))
                )
                .padding(.horizontal)

                Spacer()
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { touchLocation = $0.location }
                .onEnded { _ in touchLocation = nil }
        )
    }

    private func signIn() {
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !address.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            return
        }
        errorMessage = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                try await appState.signIn(email: address, password: password)
            } catch {
                errorMessage = "That email and password did not match."
            }
        }
    }
}
