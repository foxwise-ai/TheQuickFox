import AppKit

extension NSImage {
    /// Saves the image to a specified path.
    ///
    /// - Parameters:
    ///   - url: The file URL to save the image to.
    ///   - fileType: The format of the image file.
    ///   - properties: A dictionary of properties to use when saving the file.
    /// - Returns: `true` if the image was saved successfully, otherwise `false`.
    @discardableResult
    func save(
        to url: URL, as fileType: NSBitmapImageRep.FileType,
        properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
    ) -> Bool {
        guard let tiffRepresentation = self.tiffRepresentation,
            let bitmapImageRep = NSBitmapImageRep(data: tiffRepresentation)
        else {
            return false
        }

        guard let imageData = bitmapImageRep.representation(using: fileType, properties: properties)
        else {
            return false
        }

        do {
            try imageData.write(to: url)
            return true
        } catch {
            print("Failed to save image: \(error)")
            return false
        }
    }
}
