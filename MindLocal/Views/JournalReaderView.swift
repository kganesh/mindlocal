import SwiftUI
import UIKit

/// Reads the journal as a book: swipe to turn pages (real page-curl), each entry
/// a diary page. Opens at the tapped entry; Edit opens the structured editor.
struct JournalReaderView: View {
    let entries: [Experience]
    @State private var index: Int

    init(entries: [Experience], startIndex: Int) {
        self.entries = entries
        _index = State(initialValue: max(0, min(startIndex, entries.count - 1)))
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView("Nothing to read", systemImage: "book")
            } else {
                PageCurlReader(entries: entries, index: $index)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle(entries.indices.contains(index)
                         ? entries[index].timelineDate.formatted(.dateTime.month().day().year())
                         : "Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if entries.indices.contains(index) {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ExperienceDetailView(experience: entries[index])
                    } label: {
                        Text("Edit")
                    }
                }
            }
        }
    }
}

/// Wraps UIPageViewController's page-curl transition around DiaryPageContent
/// pages so turning a journal page feels like a real book.
private struct PageCurlReader: UIViewControllerRepresentable {
    let entries: [Experience]
    @Binding var index: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal
        )
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.setViewControllers(
            [context.coordinator.controller(for: index)],
            direction: .forward, animated: false
        )
        // Let vertical drags scroll a long entry; only horizontal drags turn the
        // page. Without this, the page-curl pan fights the ScrollView.
        for case let pan as UIPanGestureRecognizer in pvc.gestureRecognizers {
            pan.delegate = context.coordinator
        }
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: PageCurlReader
        init(_ parent: PageCurlReader) { self.parent = parent }

        /// Only begin the page-curl pan when the drag is clearly horizontal, so
        /// vertical (and even diagonal) drags fall through to the entry's scroll
        /// view. Horizontal must dominate by this factor to turn the page.
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer, let view = pan.view else { return true }
            let velocity = pan.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y) * 2.5
        }

        /// Don't let the curl pan recognize alongside the scroll view's pan.
        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }

        func controller(for idx: Int) -> UIViewController {
            let host = UIHostingController(rootView: DiaryPageContent(experience: parent.entries[idx]))
            host.view.tag = idx
            return host
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerBefore vc: UIViewController) -> UIViewController? {
            let idx = vc.view.tag
            return idx > 0 ? controller(for: idx - 1) : nil
        }

        func pageViewController(_ pvc: UIPageViewController,
                                viewControllerAfter vc: UIViewController) -> UIViewController? {
            let idx = vc.view.tag
            return idx < parent.entries.count - 1 ? controller(for: idx + 1) : nil
        }

        func pageViewController(_ pvc: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed, let current = pvc.viewControllers?.first else { return }
            parent.index = current.view.tag
        }
    }
}
