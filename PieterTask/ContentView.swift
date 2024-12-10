//
//  ContentView.swift
//  PieterTask
//
//  Created by Pieter Yoshua Natanael on 06/12/24.
//



import Foundation
import SwiftUI
import Combine

// MARK: - Models

/// Represents a single song with unique identification
struct Song: Identifiable, Codable, Equatable {
    let id: UUID
    let trackName: String
    let artistName: String
    let albumName: String
    let previewUrl: String?
    let artworkUrl: String?
    
    // Custom initializer to ensure consistent ID generation
    init(id: UUID = UUID(), trackName: String, artistName: String, albumName: String, previewUrl: String? = nil, artworkUrl: String? = nil) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.previewUrl = previewUrl
        self.artworkUrl = artworkUrl
    }
}

/// Represents a playlist containing multiple songs
struct Playlist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var songs: [Song]
    
    init(id: UUID = UUID(), name: String, songs: [Song] = []) {
        self.id = id
        self.name = name
        self.songs = songs
    }
}

// MARK: - Networking Service

/// Handles iTunes search API interactions
class ITunesSearchService {
    /// Defines potential search errors
    enum SearchError: Error {
        case invalidURL
        case networkError
        case decodingError
    }
    
    /// Intermediate struct for decoding iTunes API response
    private struct ITunesSearchResponse: Codable {
        let results: [ITunesSong]
    }
    
    /// iTunes song representation for API mapping
    private struct ITunesSong: Codable {
        let trackName: String
        let artistName: String
        let collectionName: String
        let previewUrl: String?
        let artworkUrl100: String?
    }
    
    /// Search songs using iTunes API
    /// - Parameter query: Search text for songs
    /// - Returns: Publisher of Song array or error
    func searchSongs(query: String) -> AnyPublisher<[Song], Error> {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&entity=song") else {
            return Fail(error: SearchError.invalidURL).eraseToAnyPublisher()
        }
        
        return URLSession.shared.dataTaskPublisher(for: url)
            .map { $0.data }
            .decode(type: ITunesSearchResponse.self, decoder: JSONDecoder())
            .map { response in
                response.results.map { itunesSong in
                    Song(
                        trackName: itunesSong.trackName,
                        artistName: itunesSong.artistName,
                        albumName: itunesSong.collectionName,
                        previewUrl: itunesSong.previewUrl,
                        artworkUrl: itunesSong.artworkUrl100
                    )
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

// MARK: - Playlist Management

/// Manages playlist storage and persistence
class PlaylistStore: ObservableObject {
    @Published var playlists: [Playlist] = []
    private let playlistsKey = "savedPlaylists"
    
    init() {
        loadPlaylists()
    }
    
    /// Add a new playlist
    /// - Parameter name: Name of the playlist
    func addPlaylist(name: String) {
        let newPlaylist = Playlist(name: name)
        playlists.append(newPlaylist)
        savePlaylists()
    }
    
    /// Add a song to a specific playlist
    /// - Parameters:
    ///   - playlistId: Unique identifier of the playlist
    ///   - song: Song to be added
    func addSongToPlaylist(playlistId: UUID, song: Song) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        playlists[index].songs.append(song)
        savePlaylists()
    }
    
    /// Save playlists to UserDefaults
    private func savePlaylists() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: playlistsKey)
        }
    }
    
    /// Load playlists from UserDefaults
    private func loadPlaylists() {
        guard let savedPlaylists = UserDefaults.standard.data(forKey: playlistsKey) else { return }
        let decoder = JSONDecoder()
        playlists = (try? decoder.decode([Playlist].self, from: savedPlaylists)) ?? []
    }
}



import SwiftUI
import Combine

// MARK: - Song Search View

struct SongSearchView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var playlistStore: PlaylistStore
    
    @State private var searchText = ""
    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    let playlist: Playlist
    private let searchService = ITunesSearchService()
    
    var body: some View {
        VStack {
            searchField
            
            if isLoading {
                ProgressView()
            } else if let errorMessage = errorMessage {
                errorMessageView(errorMessage)
            } else {
                songListView
            }
        }
        .navigationTitle("Add Songs")
       
        .onChange(of: searchText) { newValue in
            searchSongs(query: newValue)
        }
    }
    
    // MARK: - Subviews
       
    private var searchField: some View {
        HStack {
            TextField("Search Songs", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            Button(action: {
                searchText = "" // Clear the search text
                presentationMode.wrappedValue.dismiss() // Dismiss the view
            }) {
                Text("Cancel")
                    .foregroundColor(.blue)
            }
            .padding(.trailing) // Add padding for spacing
        }
    }


    
    private var songListView: some View {
        List(songs) { song in
            songRowView(song)
        }
    }
    
    private func songRowView(_ song: Song) -> some View {
        HStack {
            songArtworkView(song)
            songDetailsView(song)
            Spacer()
            addSongButton(song)
        }
    }
    
    private func songArtworkView(_ song: Song) -> some View {
        Group {
            if let artworkUrl = song.artworkUrl, let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .cornerRadius(5)
                } placeholder: {
                    placeholderImageView()
                }
            } else {
                placeholderImageView()
            }
        }
    }
    
    private func placeholderImageView() -> some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)
            .foregroundColor(.gray)
    }
    
    private func songDetailsView(_ song: Song) -> some View {
        VStack(alignment: .leading) {
            Text(song.trackName)
                .font(.headline)
            Text(song.artistName)
                .font(.subheadline)
        }
    }
    
    private func addSongButton(_ song: Song) -> some View {
        Button(action: {
            saveSongToPlaylist(song)
        }) {
            Image(systemName: "plus.circle")
        }
    }
    
    private func errorMessageView(_ message: String) -> some View {
        Text(message)
            .foregroundColor(.red)
    }
    
    
    
    // MARK: - Private Methods
    
    private func searchSongs(query: String) {
        guard !query.isEmpty else {
            songs = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        cancellables.removeAll()
        
        searchService.searchSongs(query: query)
            .sink(receiveCompletion: handleSearchCompletion, receiveValue: updateSongs)
            .store(in: &cancellables)
    }
    
    private func handleSearchCompletion(_ completion: Subscribers.Completion<Error>) {
        isLoading = false
        
        switch completion {
        case .failure(let error):
            errorMessage = "Search failed: \(error.localizedDescription)"
        case .finished:
            break
        }
    }
    
    private func updateSongs(_ fetchedSongs: [Song]) {
        songs = fetchedSongs
    }
    
    private func saveSongToPlaylist(_ song: Song) {
        playlistStore.addSongToPlaylist(playlistId: playlist.id, song: song)
        presentationMode.wrappedValue.dismiss()
    }
}



// MARK: - Playlist Detail View

struct PlaylistDetailView: View {
    @EnvironmentObject var playlistStore: PlaylistStore
    @State private var playlist: Playlist
    @State private var isSearchPresented = false
    
    init(playlist: Playlist) {
        _playlist = State(initialValue: playlist)
    }
    
    var body: some View {
        VStack {
            playlistHeader
            songList
        }
        .navigationBarItems(trailing: addSongButton)
        .sheet(isPresented: $isSearchPresented) {
            SongSearchView(playlist: playlist)
        }
        .onAppear(perform: updatePlaylist)
        .onChange(of: playlistStore.playlists) { _ in updatePlaylist() }
    }
    
    private var playlistHeader: some View {
        HStack {
            VStack(alignment: .leading){
                Text(playlist.name)
                    .font(.title)
                    .fontWeight(.bold)
                Text("\(playlist.songs.count) Songs")
                    .foregroundColor(.gray)
            }
            .padding()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var songList: some View {
        List(playlist.songs) { song in
            songRowView(song)
        }
    }
    
    private func songRowView(_ song: Song) -> some View {
        HStack {
            songArtworkView(song)
            songDetailsView(song)
        }
    }
    
    private func songArtworkView(_ song: Song) -> some View {
        Group {
            if let artworkUrl = song.artworkUrl, let url = URL(string: artworkUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .cornerRadius(5)
                } placeholder: {
                    placeholderImageView()
                }
            } else {
                placeholderImageView()
            }
        }
    }
    
    private func placeholderImageView() -> some View {
        Image(systemName: "photo")
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)
            .foregroundColor(.gray)
    }
    
    private func songDetailsView(_ song: Song) -> some View {
        VStack(alignment: .leading) {
            Text(song.trackName)
                .font(.headline)
            Text(song.artistName)
                .font(.subheadline)
        }
    }
    
    private var addSongButton: some View {
        Button(action: { isSearchPresented = true }) {
            Image(systemName: "plus")
        }
    }
    
    private func updatePlaylist() {
        if let updatedPlaylist = playlistStore.playlists.first(where: { $0.id == playlist.id }) {
            playlist = updatedPlaylist
        }
    }
}

// MARK: - Library View

struct LibraryView: View {
    @EnvironmentObject var playlistStore: PlaylistStore
    @State private var viewMode: ViewMode = .list
    @State private var showingAddPlaylistSheet = false
    @State private var showingPopup = false
    @State private var newPlaylistName = ""
    
    enum ViewMode {
        case list, grid
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    headerSection
                    viewModeContent
                }
                .navigationBarHidden(true)
                .sheet(isPresented: $showingAddPlaylistSheet) { // Changed from .alert to .sheet
                                    sheetContent
                                }
                PopUpView(
                                             isVisible: $showingPopup,
                                             showingAddPlaylistAlert: $showingAddPlaylistSheet // Bind to sheet instead of alert
                                         )
            }
        }
    }
    
    private var headerSection: some View {
        VStack {
            HStack {
                userProfileImage
                headerTitle
                Spacer()
                actionButtons
            }
            .padding()
            Text("Playlist")
                       .font(.headline)
                       .padding(.horizontal, 16)
                       .padding(.vertical, 6)
                       .background(Capsule().fill(Color.gray.opacity(0.2)))
                       .frame(maxWidth: .infinity, alignment: .leading)
        }
        
    }
    
    private var userProfileImage: some View {
        Image("Image1")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
            .clipShape(Circle())
    }
    
    private var headerTitle: some View {
        Text("Your Library")
            .font(.title)
            .fontWeight(.bold)
    }
    
    private var actionButtons: some View {
        VStack(alignment: .trailing, spacing: 10) {
            addPlaylistButton
            toggleViewModeButton
        }
    }
    
    private var addPlaylistButton: some View {
        Button(action: {  showingPopup = true }) {
            Image(systemName: "plus")
                .actionButtonStyle()
        }
    }
    
    private var toggleViewModeButton: some View {
        Button(action: {
            viewMode = viewMode == .list ? .grid : .list
        }) {
            Image(systemName: viewMode == .list ? "square.grid.2x2" : "list.bullet")
                .actionButtonStyle()
        }
    }
    
    private var viewModeContent: some View {
        Group {
            if viewMode == .grid {
                gridView
            } else {
                tableView
            }
        }
    }
    
    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(playlistStore.playlists) { playlist in
                    playlistCell(playlist)
                }
            }
            .padding()
        }
    }
    
    private var tableView: some View {
        List {
            ForEach(playlistStore.playlists) { playlist in
                playlistCell(playlist)
            }
        }
    }
    
    private func playlistCell(_ playlist: Playlist) -> some View {
        NavigationLink(destination: PlaylistDetailView(playlist: playlist)) {
            HStack {
                playlistImageView(for: playlist)
                playlistDetails(for: playlist)
            }
            .padding(8)
        }
    }
    
    private func playlistImageView(for playlist: Playlist) -> some View {
        Group {
            if playlist.songs.isEmpty {
                emptyPlaylistImage
            } else if playlist.songs.count <= 3 {
                singleSongImage(for: playlist)
            } else {
                multiSongImageCollage(for: playlist)
            }
        }
    }
    
    private var emptyPlaylistImage: some View {
        Image(systemName: "music.note")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 50, height: 50)
            .foregroundColor(.gray)
    }
    
    private func singleSongImage(for playlist: Playlist) -> some View {
        AsyncImage(url: URL(string: playlist.songs.first?.artworkUrl ?? "")) { image in
            image.resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .cornerRadius(8)
        } placeholder: {
            emptyPlaylistImage
        }
    }
    
    private func multiSongImageCollage(for playlist: Playlist) -> some View {
        HStack(spacing: 2) {
            VStack(spacing: 2) {
                songThumbnail(playlist.songs[0])
                songThumbnail(playlist.songs[1])
            }
            VStack(spacing: 2) {
                songThumbnail(playlist.songs[2])
                songThumbnail(playlist.songs[3])
            }
        }
    }
    
    private var sheetContent: some View { // This is the sheet content, which was the previous alertContent
            VStack {
                Text("Name your playlist.")
                    .bold()
                TextField("My first library", text: $newPlaylistName)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                HStack {
                    Button("Confirm", action: createPlaylist)
                        .bold()
                        .padding(.vertical, 12) // Increase vertical padding for a taller button
                                      .padding(.horizontal, 30) // Increase horizontal padding to make it longer
                                      .background(Color.green) // Green background
                                      .foregroundColor(.black) // White text color
                                      .cornerRadius(25) // Pill shape
                                      .frame(minWidth: 200)
                }
                .padding()
            }
            .padding()
        }
    
    private func songThumbnail(_ song: Song) -> some View {
        AsyncImage(url: URL(string: song.artworkUrl ?? "")) { image in
            image.resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 25, height: 25)
                .clipped()
        } placeholder: {
            Image(systemName: "music.note")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 25, height: 25)
                .foregroundColor(.gray)
        }
    }
    
    private func playlistDetails(for playlist: Playlist) -> some View {
        VStack(alignment: .leading) {
            Text(playlist.name)
                .font(.headline)
            Text("Playlist • \(playlist.songs.count) songs")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
    
    private var alertContent: some View {
        Group {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Create", action: createPlaylist)
            Button("Cancel", role: .cancel) {}
        }
    }
    
    private func createPlaylist() {
        guard !newPlaylistName.isEmpty else { return }
        playlistStore.addPlaylist(name: newPlaylistName)
        newPlaylistName = ""
        showingAddPlaylistSheet = false
    }
}


struct PopUpView: View {
    @Binding var isVisible: Bool
    @Binding var showingAddPlaylistAlert: Bool

    var body: some View {
        if isVisible {
            ZStack {
                // Background dimmed layer
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isVisible = false
                    }

                VStack {
                    Button(action: {
                        // Perform action for the entire button tap
                        print("Playlist tapped")
                        isVisible = false
                        showingAddPlaylistAlert = true
                    }) {
                        HStack {
                            Image(systemName: "music.note.house.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text("Playlist")
                                    .font(.headline)
                                Text("Create a playlist with a song")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                    }
                    .buttonStyle(PlainButtonStyle()) // Prevent default button styling
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .cornerRadius(10)
                .shadow(radius: 10)
                .padding(.horizontal)
                .padding(.bottom, 10) // Add some bottom spacing
                .frame(maxHeight: .infinity, alignment: .bottom) // Align to bottom
                .transition(.move(edge: .bottom)) // Animate from bottom
            }
            .animation(.easeInOut, value: isVisible)
        }
    }
}

struct PopUp: View {
    @State private var showPopup = false

    var body: some View {
        ZStack {
            Button("Show Popup") {
                showPopup = true
            }
            .font(.title)
            
            // Display PopUpView when showPopup is true
            if showPopup {
                PopUpView(isVisible: $showPopup, showingAddPlaylistAlert: $showPopup)
            }
        }
    }
}


      




// MARK: - Style Extensions

extension View {
    func actionButtonStyle() -> some View {
        self.padding(8)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(10)
    }
}

// MARK: - Content View

struct ContentView: View {
    var body: some View {
        LibraryView()
            .environmentObject(PlaylistStore())
    }
}

#Preview {
    MainAppView()
        .environmentObject(PlaylistStore())
}

