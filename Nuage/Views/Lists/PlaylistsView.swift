//
//  PlaylistsView.swift
//  Nuage
//
//  Created by hdmi1519 on 03.10.2026.
//

import SwiftUI
import Combine
import SoundCloud
import Introspect
import UniformTypeIdentifiers

enum PlaylistFilterTab: String, CaseIterable, Identifiable {
    case all
    case created
    case liked

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: return "playlists.all"
        case .created: return "playlists.created"
        case .liked: return "playlists.liked"
        }
    }
}

struct PlaylistsView: View {

    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    @Environment(\.toggleLikePlaylist) private var toggleLikePlaylist: (AnyPlaylist) -> () -> ()
    @Environment(\.toggleRepostPlaylist) private var toggleRepostPlaylist: (UserPlaylist) -> () -> ()
    @Environment(\.deletePlaylist) private var deletePlaylist: (UserPlaylist) -> ()
    @Environment(\.saveCreatedPlaylist) private var saveCreatedPlaylist: (UserPlaylist) -> ()
    @Environment(\.updateUserPlaylist) private var updateUserPlaylist: (UserPlaylist) -> ()
    @Environment(\.reloadPlaylists) private var reloadPlaylists: () -> ()
    @EnvironmentObject private var player: StreamPlayer
    @EnvironmentObject private var commands: CommandSubject

    @State private var filterTab: PlaylistFilterTab = .all
    @State private var filter = ""
    @State private var isSearching = false

    // Create Playlist Sheet State
    @State private var isShowingCreateSheet = false
    @State private var newPlaylistTitle = ""
    @State private var newPlaylistDescription = ""
    @State private var newPlaylistIsPublic = true
    @State private var newArtworkData: Data? = nil
    @State private var newArtworkImage: NSImage? = nil
    @State private var isCreating = false

    // Edit Playlist Sheet State
    @State private var playlistToEdit: UserPlaylist? = nil
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var editIsPublic = true
    @State private var editArtworkData: Data? = nil
    @State private var editArtworkImage: NSImage? = nil
    @State private var isSavingEdit = false

    // Delete Alert State
    @State private var playlistToDelete: UserPlaylist? = nil
    @State private var isShowingDeleteAlert = false

    @State private var subscriptions = Set<AnyCancellable>()

    private var currentUserID: String? {
        SoundCloud.shared.user?.id
    }

    private func isOwner(of playlist: AnyPlaylist) -> Bool {
        if let currentUserID = currentUserID, playlist.user.id == currentUserID {
            return true
        }
        if let userP = playlist.userPlaylist, userP.secretToken != nil {
            return true
        }
        return false
    }

    private var filteredPlaylists: [AnyPlaylist] {
        playlists.filter { playlist in
            let owner = isOwner(of: playlist)

            // Tab filter
            switch filterTab {
            case .all:
                break
            case .created:
                if !owner { return false }
            case .liked:
                if owner { return false }
            }

            // Filter query
            let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !query.isEmpty {
                let matchesTitle = playlist.title.lowercased().contains(query)
                let matchesUser = playlist.user.username.lowercased().contains(query)
                return matchesTitle || matchesUser
            }

            return true
        }
    }

    private var createdCount: Int {
        playlists.filter { isOwner(of: $0) }.count
    }

    private var likedCount: Int {
        playlists.filter { !isOwner(of: $0) }.count
    }

    private func stopFiltering() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isSearching = false
            filter = ""
        }
    }

    private func createPlaylist() {
        let title = newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isCreating = true

        let artworkData = newArtworkData
        SoundCloud.shared.get(.createPlaylist(title: title, description: newPlaylistDescription, isPublic: newPlaylistIsPublic))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    self.isCreating = false
                    print("Failed to create playlist: \(error)")
                }
            }, receiveValue: { created in
                if let data = artworkData {
                    SoundCloud.shared.uploadPlaylistArtwork(id: created.id, imageData: data)
                        .receive(on: RunLoop.main)
                        .sink(receiveCompletion: { _ in
                            self.finishCreating(created)
                        }, receiveValue: { updated in
                            self.finishCreating(updated)
                        })
                        .store(in: &self.subscriptions)
                } else {
                    self.finishCreating(created)
                }
            })
            .store(in: &subscriptions)
    }

    private func finishCreating(_ playlist: UserPlaylist) {
        saveCreatedPlaylist(playlist)
        isShowingCreateSheet = false
        newPlaylistTitle = ""
        newPlaylistDescription = ""
        newPlaylistIsPublic = true
        newArtworkData = nil
        newArtworkImage = nil
        isCreating = false
        reloadPlaylists()
    }

    private func saveEdit() {
        guard let target = playlistToEdit else { return }
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isSavingEdit = true

        let artworkData = editArtworkData
        SoundCloud.shared.get(.updatePlaylist(id: target.id, title: title, description: editDescription, isPublic: editIsPublic))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    self.isSavingEdit = false
                    print("Failed to update playlist: \(error)")
                }
            }, receiveValue: { updated in
                if let data = artworkData {
                    SoundCloud.shared.uploadPlaylistArtwork(id: updated.id, imageData: data)
                        .receive(on: RunLoop.main)
                        .sink(receiveCompletion: { _ in
                            self.finishEditing(updated)
                        }, receiveValue: { artworkUpdated in
                            self.finishEditing(artworkUpdated)
                        })
                        .store(in: &self.subscriptions)
                } else {
                    self.finishEditing(updated)
                }
            })
            .store(in: &subscriptions)
    }

    private func finishEditing(_ updated: UserPlaylist) {
        updateUserPlaylist(updated)
        playlistToEdit = nil
        editArtworkData = nil
        editArtworkImage = nil
        isSavingEdit = false
        reloadPlaylists()
    }

    private func confirmDelete() {
        guard let target = playlistToDelete else { return }
        deletePlaylist(target)
        playlistToDelete = nil
    }

    private func pickArtwork(forEditing: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = NSLocalizedString("playlists.chooseArtwork", comment: "")
        if panel.runModal() == .OK, let url = panel.url {
            if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                if forEditing {
                    editArtworkData = data
                    editArtworkImage = img
                } else {
                    newArtworkData = data
                    newArtworkImage = img
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter Bar (opened via Toolbar Filter Button or Cmd+F)
            if isSearching {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField(LocalizedStringKey("menu.filter"), text: $filter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .introspectTextField { field in
                            field.focusRingType = .none
                            if field.window?.firstResponder != field {
                                field.becomeFirstResponder()
                            }
                        }

                    if !filter.isEmpty {
                        Button {
                            filter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onExitCommand(perform: stopFiltering)
            }

            // Controls Bar
            HStack(spacing: 8) {
                tabChip(for: .all, icon: "square.stack.fill", count: playlists.count)
                tabChip(for: .created, icon: "folder.fill", count: createdCount)
                tabChip(for: .liked, icon: "heart.fill", count: likedCount)

                Spacer()

                // "+ New Playlist" button
                Button {
                    newPlaylistTitle = ""
                    newPlaylistDescription = ""
                    newPlaylistIsPublic = true
                    newArtworkData = nil
                    newArtworkImage = nil
                    isShowingCreateSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(LocalizedStringKey("playlists.new"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(hex: 0xFF5500))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            // List / Empty state
            if filteredPlaylists.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(LocalizedStringKey("playlists.empty"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    Text(LocalizedStringKey("playlists.emptyDescription"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)

                    Button {
                        newPlaylistTitle = ""
                        newPlaylistDescription = ""
                        newPlaylistIsPublic = true
                        newArtworkData = nil
                        newArtworkImage = nil
                        isShowingCreateSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text(LocalizedStringKey("playlists.new"))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color(hex: 0xFF5500))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filteredPlaylists) { playlist in
                            PlaylistRow(playlist: playlist)
                                .contextMenu {
                                    if let userP = playlist.userPlaylist {
                                        Button(LocalizedStringKey("context.play")) {
                                            SoundCloud.shared.get(.userPlaylist(userP.id))
                                                .receive(on: RunLoop.main)
                                                .sink(receiveCompletion: { _ in }, receiveValue: { p in
                                                    if let ids = p.trackIDs, !ids.isEmpty {
                                                        SoundCloud.shared.get(.tracks(ids))
                                                            .receive(on: RunLoop.main)
                                                            .sink(receiveCompletion: { _ in }, receiveValue: { tracks in
                                                                self.player.play(tracks, from: 0)
                                                            })
                                                            .store(in: &self.subscriptions)
                                                    }
                                                })
                                                .store(in: &subscriptions)
                                        }
                                    }

                                    Divider()

                                    if !isOwner(of: playlist) {
                                        let isLiked = playlists.contains(where: { $0.id == playlist.id })
                                        Button(LocalizedStringKey(isLiked ? "context.unlike" : "context.like"), action: toggleLikePlaylist(playlist))
                                    }
                                    if let userP = playlist.userPlaylist {
                                        Button(LocalizedStringKey("context.repost"), action: toggleRepostPlaylist(userP))
                                    }

                                    Button(LocalizedStringKey("context.copyLink")) {
                                        let text = playlist.permalinkURL.absoluteString
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(text, forType: .string)
                                    }

                                    Button(LocalizedStringKey("context.shareToFriend")) {
                                        NotificationCenter.default.post(name: .sharePlaylistToFriend, object: playlist)
                                    }

                                    if isOwner(of: playlist), let userP = playlist.userPlaylist {
                                        Divider()
                                        Button(LocalizedStringKey("playlists.edit")) {
                                            editTitle = userP.title
                                            editDescription = userP.description ?? ""
                                            editIsPublic = userP.isPublic
                                            editArtworkData = nil
                                            editArtworkImage = nil
                                            playlistToEdit = userP
                                        }
                                        Button(role: .destructive) {
                                            playlistToDelete = userP
                                            isShowingDeleteAlert = true
                                        } label: {
                                            Label(NSLocalizedString("playlists.delete", comment: ""), systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                }
                .introspectScrollView { scrollView in
                    scrollView.scrollerStyle = .overlay
                    scrollView.verticalScroller?.controlSize = .small
                }
            }
        }
        .onReceive(commands.filter) {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSearching {
                    stopFiltering()
                } else {
                    isSearching = true
                }
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            createPlaylistSheet
        }
        .sheet(item: $playlistToEdit) { target in
            editPlaylistSheet(for: target)
        }
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(LocalizedStringKey("playlists.delete")),
                message: Text(LocalizedStringKey("playlists.deleteConfirm")),
                primaryButton: .destructive(Text(LocalizedStringKey("playlists.delete")), action: confirmDelete),
                secondaryButton: .cancel(Text(LocalizedStringKey("playlists.cancel")))
            )
        }
    }

    @ViewBuilder
    private func tabChip(for tab: PlaylistFilterTab, icon: String, count: Int) -> some View {
        let isSelected = filterTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                filterTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))

                Text(tab.titleKey)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))

                Text("\(count)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.24) : Color.primary.opacity(0.08))
                    )
                    .foregroundColor(isSelected ? .white : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(isSelected ? .white : .primary.opacity(0.85))
            .background(
                Capsule()
                    .fill(isSelected ? Color(hex: 0xFF5500) : Color(nsColor: .quaternaryLabelColor))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create Playlist Sheet

    @ViewBuilder
    private var createPlaylistSheet: some View {
        VStack(spacing: 16) {
            Text(LocalizedStringKey("playlists.new"))
                .font(.system(size: 16, weight: .bold))

            // Artwork selector
            HStack(spacing: 14) {
                ZStack {
                    if let image = newArtworkImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .quaternaryLabelColor))
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button(LocalizedStringKey("playlists.chooseArtwork")) {
                        pickArtwork(forEditing: false)
                    }
                    .font(.system(size: 12))

                    if newArtworkData != nil {
                        Button(LocalizedStringKey("playlists.removeArtwork")) {
                            newArtworkData = nil
                            newArtworkImage = nil
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("playlists.namePlaceholder"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                TextField(NSLocalizedString("playlists.namePlaceholder", comment: ""), text: $newPlaylistTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("playlists.descriptionPlaceholder"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                TextEditor(text: $newPlaylistDescription)
                    .frame(height: 70)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }

            Toggle(LocalizedStringKey("playlists.public"), isOn: $newPlaylistIsPublic)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(LocalizedStringKey("playlists.cancel")) {
                    isShowingCreateSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(LocalizedStringKey("playlists.create")) {
                    createPlaylist()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newPlaylistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 380)
    }

    // MARK: - Edit Playlist Sheet

    @ViewBuilder
    private func editPlaylistSheet(for target: UserPlaylist) -> some View {
        VStack(spacing: 16) {
            Text(LocalizedStringKey("playlists.edit"))
                .font(.system(size: 16, weight: .bold))

            // Artwork selector
            HStack(spacing: 14) {
                ZStack {
                    if let image = editArtworkImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else if let url = target.artworkURL {
                        RemoteImage(url: url, cornerRadius: 10)
                            .frame(width: 72, height: 72)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .quaternaryLabelColor))
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button(LocalizedStringKey("playlists.chooseArtwork")) {
                        pickArtwork(forEditing: true)
                    }
                    .font(.system(size: 12))

                    if editArtworkData != nil {
                        Button(LocalizedStringKey("playlists.revertArtwork")) {
                            editArtworkData = nil
                            editArtworkImage = nil
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("playlists.namePlaceholder"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                TextField(NSLocalizedString("playlists.namePlaceholder", comment: ""), text: $editTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("playlists.descriptionPlaceholder"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                TextEditor(text: $editDescription)
                    .frame(height: 70)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }

            Toggle(LocalizedStringKey("playlists.public"), isOn: $editIsPublic)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(LocalizedStringKey("playlists.cancel")) {
                    playlistToEdit = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(LocalizedStringKey("playlists.save")) {
                    saveEdit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingEdit)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 380)
    }
}
