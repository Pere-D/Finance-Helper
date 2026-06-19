import SwiftUI
import SwiftData

// MARK: - Profile Pill (shown in toolbar of each main tab)

struct ProfilePill: View {
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @State private var showingManagement = false

    private var activeProfile: UserProfile? {
        profiles.first { $0.id.uuidString == activeProfileID }
    }

    var body: some View {
        Button {
            showingManagement = true
        } label: {
            HStack(spacing: 4) {
                if let profile = activeProfile {
                    Text(profile.emoji).font(.caption)
                    Text(profile.name).font(.subheadline.weight(.semibold))
                } else {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.caption)
                    Text(NSLocalizedString("no_profile", comment: "")).font(.subheadline.weight(.medium))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.systemFill))
            .foregroundStyle(Color(.label))
            .clipShape(Capsule())
        }
        .sheet(isPresented: $showingManagement) {
            ProfileManagementView()
        }
    }
}

// MARK: - Profile Management Sheet

struct ProfileManagementView: View {
    @AppStorage("active_profile_id") private var activeProfileID: String = ""
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases

    @State private var showingCreate = false
    @State private var showingPaywall = false
    @State private var profileToRename: UserProfile?
    @State private var profileToDelete: UserProfile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(profiles) { profile in
                        profileRow(profile)
                    }

                    Button {
                        if !purchases.isPremium && profiles.count >= 1 {
                            showingPaywall = true
                        } else {
                            showingCreate = true
                        }
                    } label: {
                        Label(NSLocalizedString("new_profile", comment: ""), systemImage: "plus.circle")
                            .foregroundStyle(.blue)
                    }
                } footer: {
                    Text(NSLocalizedString("profile_footer", comment: ""))
                        .font(.caption)
                }
            }
            .navigationTitle(NSLocalizedString("profiles", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("done", comment: "")) { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
        .alert(NSLocalizedString("delete_account_confirm_title", comment: ""),
               isPresented: Binding(get: { profileToDelete != nil },
                                    set: { if !$0 { profileToDelete = nil } })) {
            Button(NSLocalizedString("delete", comment: ""), role: .destructive) {
                if let p = profileToDelete { deleteProfile(p) }
                profileToDelete = nil
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            if let p = profileToDelete {
                Text("\(p.name) – \(NSLocalizedString("delete_account_confirm_message", comment: ""))")
            }
        }
        .sheet(isPresented: $showingCreate) {
            CreateProfileView { name, emoji in
                let profile = UserProfile(name: name, emoji: emoji)
                modelContext.insert(profile)
                activeProfileID = profile.id.uuidString
            }
        }
        .sheet(item: $profileToRename) { profile in
            RenameProfileView(profile: profile)
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView().environment(purchases)
        }
    }

    private func profileRow(_ profile: UserProfile) -> some View {
        let isActive = activeProfileID == profile.id.uuidString
        return HStack(spacing: 12) {
            Button {
                activeProfileID = profile.id.uuidString
            } label: {
                HStack(spacing: 12) {
                    Text(profile.emoji)
                        .font(.title2)
                        .frame(width: 38, height: 38)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                    Text(profile.name)
                        .foregroundStyle(.primary)
                        .font(.body)
                    Spacer(minLength: 0)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                profileToRename = profile
            } label: {
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 32, height: 32)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Button {
                profileToDelete = profile
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 32, height: 32)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(isActive ? Color.blue.opacity(0.10) : nil)
    }

    private func deleteProfile(_ profile: UserProfile) {
        if activeProfileID == profile.id.uuidString {
            let remaining = profiles.filter { $0.id != profile.id }
            activeProfileID = remaining.first?.id.uuidString ?? ""
        }
        modelContext.delete(profile)
    }
}

// MARK: - Rename Profile

struct RenameProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var profile: UserProfile

    @State private var name = ""
    @State private var emoji = ""

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("account_name", comment: "")) {
                    TextField(NSLocalizedString("profile_name_placeholder", comment: ""), text: $name)
                }
                Section("Emoji") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(profileEmojis, id: \.self) { e in
                            Button { emoji = e } label: {
                                Text(e)
                                    .font(.title)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(emoji == e ? Color.blue.opacity(0.12) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.blue, lineWidth: emoji == e ? 1.5 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                }
            }
            .navigationTitle(NSLocalizedString("rename", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("done", comment: "")) {
                        profile.name = name.trimmingCharacters(in: .whitespaces)
                        profile.emoji = emoji
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            name = profile.name
            emoji = profile.emoji
        }
    }
}

// MARK: - Create Profile

struct CreateProfileView: View {
    @Environment(\.dismiss) private var dismiss
    var onCreate: (String, String) -> Void

    @State private var name = ""
    @State private var emoji = "👤"

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        NavigationStack {
            Form {
                Section(NSLocalizedString("account_name", comment: "")) {
                    TextField(NSLocalizedString("profile_name_placeholder", comment: ""), text: $name)
                }
                Section("Emoji") {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(profileEmojis, id: \.self) { e in
                            Button { emoji = e } label: {
                                Text(e)
                                    .font(.title)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(emoji == e ? Color.blue.opacity(0.12) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.blue, lineWidth: emoji == e ? 1.5 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                }
            }
            .navigationTitle(NSLocalizedString("new_profile", comment: ""))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("create", comment: "")) {
                        onCreate(name.trimmingCharacters(in: .whitespaces), emoji)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - No Profile View

struct NoProfileView: View {
    @State private var showingCreate = false
    @Environment(\.modelContext) private var modelContext
    @AppStorage("active_profile_id") private var activeProfileID: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text(NSLocalizedString("no_profile", comment: ""))
                    .font(.title2.weight(.semibold))
                Text(NSLocalizedString("no_profile_subtitle", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showingCreate = true
            } label: {
                Label(NSLocalizedString("new_profile", comment: ""), systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingCreate) {
            CreateProfileView { name, emoji in
                let profile = UserProfile(name: name, emoji: emoji)
                modelContext.insert(profile)
                activeProfileID = profile.id.uuidString
            }
        }
    }
}
