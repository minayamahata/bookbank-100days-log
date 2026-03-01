import SwiftUI
import UIKit

struct ColorPickerSheet: UIViewControllerRepresentable {
    @Binding var selectedColor: Color
    var onComplete: (() -> Void)?
    
    init(selectedColor: Binding<Color>, onComplete: (() -> Void)? = nil) {
        self._selectedColor = selectedColor
        self.onComplete = onComplete
    }
    
    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.selectedColor = UIColor(selectedColor)
        picker.supportsAlpha = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIColorPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: ColorPickerSheet
        private var hasCalledComplete = false
        
        init(_ parent: ColorPickerSheet) {
            self.parent = parent
        }
        
        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            parent.selectedColor = Color(viewController.selectedColor)
            
            if !hasCalledComplete {
                hasCalledComplete = true
                parent.onComplete?()
            }
        }
        
        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            parent.selectedColor = Color(viewController.selectedColor)
        }
    }
}
