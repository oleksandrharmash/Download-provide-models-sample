//
//  ContentLoader.swift
//
//  Created by Oleksandr Harmash
//  Copyright © Oleksandr Harmash. All rights reserved.
//

import FirebaseCore
import FirebaseDatabase

import Zip

class ContentLoader: NSObject {
    static let shared = ContentLoader()
    
    private lazy var downloadSession: URLSession = {
        let queue = OperationQueue()
        queue.name = bundleID + ".urlSessionDelegateQueue"
        queue.qualityOfService = QualityOfService.background
        
        let config = URLSessionConfiguration.background(withIdentifier: bundleID + ".downloadSession")
        config.httpMaximumConnectionsPerHost = 3
        
        return URLSession(configuration: config, delegate: self, delegateQueue:queue)
    }()
    
    private var downloadSessionCompletionHandler: (() -> Void)?

    override init() {
        super.init()
        
        //Regarding URL Session programming guide - background session should be created immediatelly after app launch
        _ = downloadSession
        
        FirebaseApp.configure()
        //Files, downloaded with background download session has .tmp extension
        Zip.addCustomFileExtension("tmp")
    }
    
    //MARK: - Public
    
    func handle(completionHandler: @escaping () -> Void, forSessionWithIdentifier identifier: String) {
        downloadSessionCompletionHandler = completionHandler
    }
    
    //MARK: - Firebase

    func checkForNewObjects() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            let databaseRef = Database.database().reference()
            let lastUpdates = DataBaseManager.shared.lastUpdates
            databaseRef.child("Furniture").queryOrdered(byChild: "updated")
                .queryStarting(atValue: lastUpdates, childKey: "updated")
                .observeSingleEvent(of: .value, with: { (snapshot) in
                    //Always called at main thread, so put it in background
                    DispatchQueue.global(qos: .background).async { [weak self] in
                        switch snapshot.value {
                        case let furnitures as [[String: AnyObject]]:
                            DataBaseManager.shared.fetched(newFurniture: furnitures)
                            
                        case let furniture as [String: AnyObject]:
                            guard let furnitures = Array(furniture.values) as? [[String : AnyObject]] else { break }
                            DataBaseManager.shared.fetched(newFurniture: furnitures)
                            
                        default: break
                        }
                        
                        self?.loadSourcesForNewModels()
                    }
                })
        }
    }
    
    //MARK: - Private
    
    private func loadSourcesForNewModels() {
        
        guard let unloadedFurnriture = DataBaseManager.shared.furnitureWithUnloadedSources() else { return }
        
        for furniture in unloadedFurnriture {
            //Furniture.sourcesLocation was checked when save it to the database
            guard let url = URL(string: furniture.sourcesLocation!) else { continue }
            let task = downloadSession.downloadTask(with: url)
            task.resume()
        }
    }

}

//MARK: - URLSessionTaskDelegate, URLSessionDownloadDelegate -

extension ContentLoader: URLSessionTaskDelegate, URLSessionDownloadDelegate {
    
    private func sourcesDownloaded(fromUrl: URL, toTempLocation location: URL) {
        guard let lastPathComponent = lastModelPathComponent(fromFullURLPath: fromUrl) else { return }
        
        let destinationURL = downloadedModelsDirectory.appendingPathComponent(lastPathComponent)
        
        do {
            try Zip.unzipFile(location, destination: destinationURL, overwrite: false, password: nil)
        } catch {
            print("Error when unzipping: \(error)")
        }
        
        DataBaseManager.shared.modelsDownloaded(to: lastPathComponent)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        
        guard let sourceUrl = downloadTask.originalRequest?.url else { return }
        sourcesDownloaded(fromUrl: sourceUrl, toTempLocation: location)
    }
    
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        if session.configuration.identifier?.isEmpty == false {
            let completion = downloadSessionCompletionHandler
            downloadSessionCompletionHandler = nil
            //Should be called on the main thread
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
}
