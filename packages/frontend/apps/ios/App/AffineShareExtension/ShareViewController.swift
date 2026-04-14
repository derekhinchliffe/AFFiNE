//
//  ShareViewController.swift
//  AffineShareExtension
//
//  Created by Derek Haines on 9/9/2025.
//

import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers
import AVFoundation

class ShareViewController: SLComposeServiceViewController {

    var sharedText: String?
    var sharedImages: [UIImage] = []
    var sharedMovies: [URL] = []

    let appGroupID = "group.au.haines.affine" // TODO: Replace with official Affine App Group ID once development is done

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
    }

    private func saveToSharedContainer(text: String?, images: [UIImage], movies: [URL]) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("Failed to get shared container URL")
            return
        }
        let uuid = UUID().uuidString
        let baseURL = containerURL.appendingPathComponent("Share-\(uuid)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
            // Save text
            if let text = text {
                let textURL = baseURL.appendingPathComponent("content.txt")
                try text.write(to: textURL, atomically: true, encoding: .utf8)
            }
            // Save images
            for (idx, image) in images.enumerated() {
                let imageURL = baseURL.appendingPathComponent("image\(idx).jpg")
                if let data = image.jpegData(compressionQuality: 0.9) {
                    try data.write(to: imageURL)
                }
            }
            // Save movies
            for (idx, movieURL) in movies.enumerated() {
                let destURL = baseURL.appendingPathComponent("movie\(idx).mov")
                try FileManager.default.copyItem(at: movieURL, to: destURL)
            }
            // Optionally, save a manifest file
            let manifest = [
                "text": text != nil,
                "imageCount": images.count,
                "movieCount": movies.count
            ] as [String : Any]
            let manifestURL = baseURL.appendingPathComponent("manifest.json")
            let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [])
            try manifestData.write(to: manifestURL)
            print("Saved shared items to \(baseURL)")
        } catch {
            print("Error saving shared items: \(error)")
        }
    }

    private func extractSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        let dispatchGroup = DispatchGroup()

        for item in extensionItems {
            if let attachments = item.attachments {
                for provider in attachments {
                    // Text
                    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        dispatchGroup.enter()
                        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { (item, error) in
                            if let text = item as? String {
                                self.sharedText = (self.sharedText ?? "") + text
                            }
                            dispatchGroup.leave()
                        }
                    }
                    // Images
                    else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier), self.sharedImages.count < 10 {
                        dispatchGroup.enter()
                        provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (item, error) in
                            if let url = item as? URL, let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                                self.sharedImages.append(image)
                            } else if let image = item as? UIImage {
                                self.sharedImages.append(image)
                            }
                            dispatchGroup.leave()
                        }
                    }
                    // Movies
                    else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier), self.sharedMovies.count < 2 {
                        dispatchGroup.enter()
                        provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { (item, error) in
                            if let url = item as? URL {
                                self.sharedMovies.append(url)
                            }
                            dispatchGroup.leave()
                        }
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            // Save to shared container
            self.saveToSharedContainer(text: self.sharedText, images: self.sharedImages, movies: self.sharedMovies)
            // Print debug info
            if let text = self.sharedText {
                print("Shared Text: \(text)")
            }
            print("Shared Images: \(self.sharedImages.count)")
            print("Shared Movies: \(self.sharedMovies.count)")
            // Optionally, open main app here via URL scheme if desired
            if let url = URL(string: "affine://share-completed") {
                _ = self.openURLInMainApp(url: url)
            }
        }
    }

    private func openURLInMainApp(url: URL) -> Bool {
        var responder: UIResponder? = self as UIResponder
        while responder != nil {
            if let application = responder as? UIApplication {
                return application.openURL(url)
            }
            responder = responder?.next
        }
        return false
    }

    override func didSelectPost() {
        // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
        extractSharedItems()
        // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }

}
