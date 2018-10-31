//
//  ModelProvider.swift
//
//  Created by Oleksandr Harmash
//  Copyright © Oleksandr Harmash. All rights reserved.
//

import SceneKit
import ARKit

class ModelProvider {
    static let shared = ModelProvider()
    
    private var loadedObjects = [String: SCNReferenceNode]()

    func loadModel(for furniture: Furniture, completion: @escaping (_ loadedObject: FurnitureNode?) -> () ) {
        DispatchQueue.global(qos: .default).async {[weak self] in
            guard let sources = furniture.sourcesLocation else {
                fatalError("Trying to add furniture without sources url")
            }

            if let loadedObject = self?.loadedObjects[sources] {
                let furniture = self?.wrap(loadedObject)
                completion(furniture)
            } else {
                guard let objectUrl = furniture.modelURL(),
                    let newObject = SCNReferenceNode(url: objectUrl) else {
                        fatalError("Can't load model at location: \(String(describing: furniture.modelURL()))")
                }
                
                newObject.load()
                self?.loadedObjects[sources] = newObject
                
                let furniture = self?.wrap(newObject)
                completion(furniture)
            }
        }
    }
    
    func appDidReceiveMemoryWarning() {
        unloadObjects()
    }
    
}

private extension ModelProvider {
    
    func wrap(_ node: SCNReferenceNode) -> FurnitureNode {
        
        let clone = node.clone()
        let newFurniture = FurnitureNode()
        
        for child in clone.childNodes {
            //needs for .obj models
            if let geometry = child.geometry {
                for material in geometry.materials {
                    material.lightingModel = .phong
                }
            }
            child.setCategoryBitMask(CategoryBitMask.virtualObject.rawValue)
            newFurniture.addChildNode(child)
        }
        
        return newFurniture
    }
    
    func unloadObjects() {
        //Objects, which not presented now - will be unload from cache
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let objects = self?.loadedObjects.values else { return }
            for object in objects {
                if object.isLoaded {
                    object.unload()
                }
            }
            self?.loadedObjects.removeAll()
        }
    }

}
