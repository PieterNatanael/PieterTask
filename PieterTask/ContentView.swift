//
//  ContentView.swift
//  PieterTask
//
//  Created by Pieter Yoshua Natanael on 06/12/24.
//


import Foundation
import SwiftUI

struct Song: Identifiable, Codable, Equatable {
    let id = UUID()
    let trackName: String
    let artistName: String
    let albumName: String
    let previewUrl: String?
    let artworkUrl: String?
}

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

// PlaylistStore.swift
import Foundation

class PlaylistStore: ObservableObject {
    @Published var playlists: [Playlist] = []
    
    private let playlistsKey = "savedPlaylists"
    
    init() {
        loadPlaylists()
    }
    
    func addPlaylist(name: String) {
        let newPlaylist = Playlist(name: name)
        playlists.append(newPlaylist)
        savePlaylists()
    }
    
    func addSongToPlaylist(playlistId: UUID, song: Song) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].songs.append(song)
            savePlaylists()
        }
    }
    
    private func savePlaylists() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: playlistsKey)
        }
    }
    
    private func loadPlaylists() {
        if let savedPlaylists = UserDefaults.standard.object(forKey: playlistsKey) as? Data {
            let decoder = JSONDecoder()
            if let loadedPlaylists = try? decoder.decode([Playlist].self, from: savedPlaylists) {
                playlists = loadedPlaylists
            }
        }
    }
}

// ITunesSearchService.swift
import Foundation
import Combine

class ITunesSearchService {
    enum SearchError: Error {
        case invalidURL
        case networkError
        case decodingError
    }
    
    struct ITunesSearchResponse: Codable {
        let results: [ITunesSong]
    }
    
    struct ITunesSong: Codable {
        let trackName: String
        let artistName: String
        let collectionName: String
        let previewUrl: String?
        let artworkUrl100: String?
    }
    
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

// SongSearchView.swift
import SwiftUI
import Combine

struct SongSearchView: View {
    @Environment(\.presentationMode) var presentationMode
   
    
    @State private var searchText = ""
    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    let playlist: Playlist
        @EnvironmentObject var playlistStore: PlaylistStore
    
    private let searchService = ITunesSearchService()
   
    
    var body: some View {
        VStack {
            TextField("Search Songs", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .onChange(of: searchText) { newValue in
                    searchSongs(query: newValue)
                }
            
            if isLoading {
                ProgressView()
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else {
                List(songs) { song in
                    HStack {
                        if let artworkUrl = song.artworkUrl, let url = URL(string: artworkUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 50) // Set size
                                    .cornerRadius(5)
                            } placeholder: {
                                ProgressView()
                            }
                        } else {
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .foregroundColor(.gray)
                        }
                        VStack(alignment: .leading) {
                            Text(song.trackName)
                                .font(.headline)
                            Text(song.artistName)
                                .font(.subheadline)
                        }
                        Spacer()
                        Button(action: {
                            saveSongToPlaylist(song)
                        }) {
                            Image(systemName: "plus.circle")
                        }
                    }
                }
        }
    }
        .navigationTitle("Add Songs")
}
    
    private func searchSongs(query: String) {
        guard !query.isEmpty else {
            songs = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        cancellables.removeAll()
        
        
        searchService.searchSongs(query: query)
            .sink(receiveCompletion: { completion in
                isLoading = false
                switch completion {
                case .failure(let error):
                    errorMessage = "Search failed: \(error.localizedDescription)"
                case .finished:
                    break
                }
            }, receiveValue: { fetchedSongs in
                songs = fetchedSongs
            })
            .store(in: &cancellables)
    }
    
    private func saveSongToPlaylist(_ song: Song) {
          playlistStore.addSongToPlaylist(playlistId: playlist.id, song: song)
          presentationMode.wrappedValue.dismiss()
      }
  }

// LibraryView.swift
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var playlistStore: PlaylistStore
    @State private var isGridView = false
    @State private var showingAddPlaylistAlert = false
    @State private var newPlaylistName = ""
    
    var body: some View {
        NavigationView {
            VStack {
                Toggle("Grid View", isOn: $isGridView)
                    .padding()
                
                if isGridView {
                    gridView
                } else {
                    tableView
                }
            }
            .navigationTitle("Library")
            .navigationBarItems(
                trailing: Button(action: {
                    showingAddPlaylistAlert = true
                }) {
                    Image(systemName: "plus")
                }
            )
            .alert("New Playlist", isPresented: $showingAddPlaylistAlert) {
                TextField("Playlist Name", text: $newPlaylistName)
                Button("Create", action: createPlaylist)
                Button("Cancel", role: .cancel) {}
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
                Text(playlist.name)
                Spacer()
                Text("\(playlist.songs.count) songs")
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func createPlaylist() {
        guard !newPlaylistName.isEmpty else { return }
        playlistStore.addPlaylist(name: newPlaylistName)
        newPlaylistName = ""
    }
}


// PlaylistDetailView.swift
import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject var playlistStore: PlaylistStore
    @State private var playlist: Playlist
    @State private var isSearchPresented = false
    
    // Initialize with the playlist
    init(playlist: Playlist) {
        _playlist = State(initialValue: playlist)
    }
    
    var body: some View {
        VStack {
            List(playlist.songs) { song in
                HStack {
                    if let artworkUrl = song.artworkUrl, let url = URL(string: artworkUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                                .cornerRadius(5)
                        } placeholder: {
                            ProgressView()
                        }
                    } else {
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.gray)
                    }
                    VStack(alignment: .leading) {
                        Text(song.trackName)
                            .font(.headline)
                        Text(song.artistName)
                            .font(.subheadline)
                    }
                }
            }
            
            Button("Add Songs") {
                isSearchPresented = true
            }
            .sheet(isPresented: $isSearchPresented) {
                SongSearchView(playlist: playlist)
            }
        }
        .navigationTitle(playlist.name)
        .onAppear {
            // Refresh the playlist from the store
            if let updatedPlaylist = playlistStore.playlists.first(where: { $0.id == playlist.id }) {
                playlist = updatedPlaylist
            }
        }
        // Add this modifier to update immediately when songs change
        .onChange(of: playlistStore.playlists) { _ in
            if let updatedPlaylist = playlistStore.playlists.first(where: { $0.id == playlist.id }) {
                playlist = updatedPlaylist
            }
        }
    }
}

    
// ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        LibraryView()
            .environmentObject(PlaylistStore())
    }
}

#Preview {
    ContentView()
        .environmentObject(PlaylistStore())
}



/*
 //want to add album image
import Foundation
import SwiftUI

struct Song: Identifiable, Codable, Equatable {
    let id = UUID()
    let trackName: String
    let artistName: String
    let albumName: String
    let previewUrl: String?
}

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

// PlaylistStore.swift
import Foundation

class PlaylistStore: ObservableObject {
    @Published var playlists: [Playlist] = []
    
    private let playlistsKey = "savedPlaylists"
    
    init() {
        loadPlaylists()
    }
    
    func addPlaylist(name: String) {
        let newPlaylist = Playlist(name: name)
        playlists.append(newPlaylist)
        savePlaylists()
    }
    
    func addSongToPlaylist(playlistId: UUID, song: Song) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].songs.append(song)
            savePlaylists()
        }
    }
    
    private func savePlaylists() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: playlistsKey)
        }
    }
    
    private func loadPlaylists() {
        if let savedPlaylists = UserDefaults.standard.object(forKey: playlistsKey) as? Data {
            let decoder = JSONDecoder()
            if let loadedPlaylists = try? decoder.decode([Playlist].self, from: savedPlaylists) {
                playlists = loadedPlaylists
            }
        }
    }
}

// ITunesSearchService.swift
import Foundation
import Combine

class ITunesSearchService {
    enum SearchError: Error {
        case invalidURL
        case networkError
        case decodingError
    }
    
    struct ITunesSearchResponse: Codable {
        let results: [ITunesSong]
    }
    
    struct ITunesSong: Codable {
        let trackName: String
        let artistName: String
        let collectionName: String
        let previewUrl: String?
    }
    
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
                        previewUrl: itunesSong.previewUrl
                    )
                }
            }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}

// SongSearchView.swift
import SwiftUI
import Combine

struct SongSearchView: View {
    @Environment(\.presentationMode) var presentationMode
   
    
    @State private var searchText = ""
    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cancellables = Set<AnyCancellable>()
    
    let playlist: Playlist
        @EnvironmentObject var playlistStore: PlaylistStore
    
    private let searchService = ITunesSearchService()
   
    
    var body: some View {
        VStack {
            TextField("Search Songs", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                .onChange(of: searchText) { newValue in
                    searchSongs(query: newValue)
                }
            
            if isLoading {
                ProgressView()
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            } else {
                List(songs) { song in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(song.trackName)
                                .font(.headline)
                            Text(song.artistName)
                                .font(.subheadline)
                        }
                        Spacer()
                        Button(action: {
                                               saveSongToPlaylist(song)
                                           }) {
                                               Image(systemName: "plus.circle")
                    }
                }
            }
        }
    }
        .navigationTitle("Add Songs")
}
    
    private func searchSongs(query: String) {
        guard !query.isEmpty else {
            songs = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        cancellables.removeAll()
        
        
        searchService.searchSongs(query: query)
            .sink(receiveCompletion: { completion in
                isLoading = false
                switch completion {
                case .failure(let error):
                    errorMessage = "Search failed: \(error.localizedDescription)"
                case .finished:
                    break
                }
            }, receiveValue: { fetchedSongs in
                songs = fetchedSongs
            })
            .store(in: &cancellables)
    }
    
    private func saveSongToPlaylist(_ song: Song) {
          playlistStore.addSongToPlaylist(playlistId: playlist.id, song: song)
          presentationMode.wrappedValue.dismiss()
      }
  }

// LibraryView.swift
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var playlistStore: PlaylistStore
    @State private var isGridView = false
    @State private var showingAddPlaylistAlert = false
    @State private var newPlaylistName = ""
    
    var body: some View {
        NavigationView {
            VStack {
                Toggle("Grid View", isOn: $isGridView)
                    .padding()
                
                if isGridView {
                    gridView
                } else {
                    tableView
                }
            }
            .navigationTitle("Library")
            .navigationBarItems(
                trailing: Button(action: {
                    showingAddPlaylistAlert = true
                }) {
                    Image(systemName: "plus")
                }
            )
            .alert("New Playlist", isPresented: $showingAddPlaylistAlert) {
                TextField("Playlist Name", text: $newPlaylistName)
                Button("Create", action: createPlaylist)
                Button("Cancel", role: .cancel) {}
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
                Text(playlist.name)
                Spacer()
                Text("\(playlist.songs.count) songs")
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func createPlaylist() {
        guard !newPlaylistName.isEmpty else { return }
        playlistStore.addPlaylist(name: newPlaylistName)
        newPlaylistName = ""
    }
}

// PlaylistDetailView.swift
import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject var playlistStore: PlaylistStore
    @State private var playlist: Playlist
    @State private var isSearchPresented = false
    
    // Initialize with the playlist
    init(playlist: Playlist) {
        _playlist = State(initialValue: playlist)
    }
    
    var body: some View {
        VStack {
            List(playlist.songs) { song in
                VStack(alignment: .leading) {
                    Text(song.trackName)
                        .font(.headline)
                    Text(song.artistName)
                        .font(.subheadline)
                }
            }
            
            Button("Add Songs") {
                isSearchPresented = true
            }
            .sheet(isPresented: $isSearchPresented) {
                SongSearchView(playlist: playlist)
            }
        }
        .navigationTitle(playlist.name)
        .onAppear {
            // Refresh the playlist from the store
            if let updatedPlaylist = playlistStore.playlists.first(where: { $0.id == playlist.id }) {
                playlist = updatedPlaylist
            }
        }
        // Add this modifier to update immediately when songs change
        .onChange(of: playlistStore.playlists) { _ in
            if let updatedPlaylist = playlistStore.playlists.first(where: { $0.id == playlist.id }) {
                playlist = updatedPlaylist
            }
        }
    }
}

    
// ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        LibraryView()
            .environmentObject(PlaylistStore())
    }
}

#Preview {
    ContentView()
        .environmentObject(PlaylistStore())
}

*/
