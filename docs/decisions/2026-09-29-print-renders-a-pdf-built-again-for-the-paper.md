# Print renders a PDF, built again for the paper

*Decided September 2026 (issue #375).*
Print does not send the reader's text view to the printer.
That view is built for the window's column, and artwork scaling and table shape are measured against the column when the document is built, so nothing laid out for the screen can be re-flowed onto paper.
Its colors are dynamic and it draws no background, so dark mode would print light text.
Its title is a hosted SwiftUI view over the text rather than part of the storage.
And AppKit's automatic pagination was designed for TextKit 1, where the reader is TextKit 2.

So a print is a build of its own.
`DocumentPDF` (in the app) builds the document at the paper's column in `PrintLayout.style`, which has no links (`ReadingStyle.emitsLinks`: paper cannot follow one, and a layout manager with no text view underlines every `.link` run), with a title block (`DocumentTextBuilder.TitleBlock`) opening the text, since paper has no header view.
It sets a reference as ordinary text, its label at medium weight in the color of the text around it, with no chip or symbol (`ReferenceStyle.plainText`): on paper a tinted, iconed chip breaks the line it sits in, and there is nothing to tap.
It lays the text out off-screen with the reader's own `RFCTextLayoutFragment`, so the cards and rules are the screen's, and draws it into a PDF context a page at a time in the light appearance, with an RFC's running header and footer.
Where pages break, and which paragraphs each page draws, is `PrintPagination`, a pure function of line and fragment positions: a page never ends inside a line or on a paragraph the builder marked as keeping with the next (`BuiltDocument.keepsWithNext`: the title and every heading), and a figure taller than a page gets a page of its own.
What the header and footer say is `PrintFurniture`, from the same merge of the document's header and the index's entry that the reader's header view shows (`HeaderSummary`).
All of these are in `RFCReaderKit` and tested there.
Layout and drawing run off the main actor.
With Original Text showing, the published text is what prints, one to one: it is split at its form feeds, and each published page is one printed page, with no running header or footer of the app's, since the page carries its own and its `[Page n]`.
It is set at 9 pt (`PrintLayout.originalTextSize`), at which a published page's 58 lines of 72 columns fit either paper; a page longer or wider than that shrinks the whole document, rather than being split, so every sheet is still one published page and every page is set the same.
Down to 7 pt and no further, below which a print is no longer read: a page still too long there continues on the next sheet, as a text with no form feeds does, and a line still too wide wraps under its own indentation (`PublishedPages`, decided on the pull request for #375).

The PDF is what reaches the system: `PDFDocument.printOperation` on the Mac, run as a sheet on the reader's window, and `UIPrintInteractionController` on iOS. The Mac lays out for the paper Page Setup chose; iOS, whose sheet chooses paper afterwards, for the region's (`PrintLayout.paperSize(for:)`); either scales to a different paper picked in the panel.

Export as PDF (#376) saves the same pages, with what a file read on screen has that paper does not.
A paper build emits no live links, but keeps where each went as `.rfcLinkTarget`, a key TextKit does not style; `PDFExport.target(of:references:)` turns each into an anchor in the file or a web URL (another RFC's page on rfc-editor.org, or where a bibliography entry points), and the renderer measures the link's words with the layout manager and adds link annotations through PDFKit.
An export is built in `PrintLayout.exportStyle`, the print's style read on screen: every link, a reference included, is underlined in the link color (`ReferenceStyle.link`), where a print sets a reference as plain text.
A print keeps no live links whatever the build: printing a PDF re-renders its pages, and link annotations do not survive it, checked by printing an annotated `PDFDocument` to a file.
The outline lists the abstract and every section the build holds (`PDFExport.outline`), and the file's info names the document (`PDFExport.Info`), its keywords ending with the working group and the status.
The Mac's save panel offers `RFC-10042.pdf` (`ExportFormat.fileName(for:)`) and the Finder tags `RFC`, the working group and the status (`ExportFormat.tagNames(for:)`), which the app sets on the file once written, as `NSSavePanel` leaves that to it; iOS's Save to Files takes the name alone.
The print panel's Save as PDF sheet is filled from the job title alone: Author, Subject, Keywords and Tags have no public setting there.
Every export goes through one `DocumentExport`, which the Mac's save panel (with a Format pop-up, `ExportFormatChooser`) and iOS's Save to Files both call, so a format is a case in `ExportFormat` and in that one switch.
A format is published (the RFC Editor's own file) or rendered (from the parsed document); PDF is rendered, and the others are #377.
