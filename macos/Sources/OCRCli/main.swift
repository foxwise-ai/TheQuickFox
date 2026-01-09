import Foundation
import AppKit
import TheQuickFoxCore

/// Simple CLI tool for running Apple Vision OCR on images
struct OCRCli {
    static func main() {
        let args = CommandLine.arguments

        // Parse arguments
        var imagePath: String?
        var jsonOutput = false
        var toonOutput = false
        var verbose = false

        var i = 1
        while i < args.count {
            let arg = args[i]

            switch arg {
            case "--json":
                jsonOutput = true
            case "--toon":
                toonOutput = true
            case "--verbose", "-v":
                verbose = true
            case "--help", "-h":
                printHelp()
                exit(0)
            default:
                if imagePath == nil && !arg.starts(with: "-") {
                    imagePath = arg
                }
            }
            i += 1
        }

        guard let path = imagePath else {
            fputs("Error: Image path required\n", stderr)
            printHelp()
            exit(1)
        }

        // Load image
        guard let image = NSImage(contentsOfFile: path) else {
            fputs("Error: Could not load image at path: \(path)\n", stderr)
            exit(1)
        }

        // Run OCR
        do {
            let result = try TextRecognizer.recognize(img: image)

            if toonOutput {
                // Output as TOON (token-efficient format for LLMs)
                let toonString = try result.toTOON()
                print(toonString)

                if verbose {
                    // Compare sizes
                    let jsonData = try JSONSerialization.data(
                        withJSONObject: [
                            "text": result.texts,
                            "observations": result.observations,
                            "latencyMs": result.latencyMs
                        ],
                        options: []
                    )
                    let savings = Double(jsonData.count - toonString.count) / Double(jsonData.count) * 100
                    fputs("\nTOON: \(toonString.count) bytes, JSON: \(jsonData.count) bytes\n", stderr)
                    fputs("Token savings: \(String(format: "%.1f", savings))%\n", stderr)
                }
            } else if jsonOutput {
                // Output as JSON
                let output: [String: Any] = [
                    "texts": result.texts,
                    "text": result.texts,  // Alias for compatibility
                    "observations": result.observations,
                    "latencyMs": result.latencyMs
                ]

                let jsonData = try JSONSerialization.data(
                    withJSONObject: output,
                    options: verbose ? [.prettyPrinted] : []
                )

                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                }
            } else {
                // Output plain text
                print(result.texts)

                if verbose {
                    fputs("\nLatency: \(String(format: "%.2f", result.latencyMs))ms\n", stderr)
                    fputs("Lines: \(result.observations.count)\n", stderr)
                }
            }

            exit(0)
        } catch {
            fputs("Error: OCR failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func printHelp() {
        let help = """

        OCR CLI - Apple Vision OCR Tool

        Usage: ocr-cli <image-path> [options]

        Options:
          --json          Output results as JSON (includes observations and metadata)
          --toon          Output results as TOON (token-efficient format, 30-50% smaller)
          --verbose, -v   Include additional information (latency, token savings)
          --help, -h      Show this help message

        Examples:
          ocr-cli screenshot.png
          ocr-cli screenshot.png --json
          ocr-cli screenshot.png --toon
          ocr-cli screenshot.png --toon --verbose

        Output Format (TOON):
          text: extracted text with newlines
          latencyMs: 123.45
          observations[N]{text,confidence,x,y,width,height}:
            line of text,0.95,10,20,200,30
            another line,0.98,10,60,180,25

        Output Format (JSON):
          {
            "texts": "extracted text with newlines",
            "text": "same as texts (alias)",
            "observations": [
              {
                "text": "line of text",
                "confidence": 0.95,
                "quad": { "topLeft": {...}, "topRight": {...}, ... }
              }
            ],
            "latencyMs": 123.45
          }

        """
        print(help)
    }
}

// Run the CLI
OCRCli.main()
