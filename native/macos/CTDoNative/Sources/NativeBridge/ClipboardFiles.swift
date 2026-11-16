import Foundation
import AppKit
public enum ClipboardFiles {
 public static func urls(from strings:[String])->[URL] {
  strings.reduce(into:[]){result,value in
   let text=value.trimmingCharacters(in:.whitespacesAndNewlines)
   let url=text.hasPrefix("file://") ? URL(string:text) : text.hasPrefix("/") ? URL(fileURLWithPath:text) : nil
   if let url,url.isFileURL {let path=(url as NSURL).filePathURL ?? url;if !result.contains(path){result.append(path)}}
  }
 }
 @MainActor public static func read(_ board:NSPasteboard)->[URL] {
  var result:[URL]=[]
  if let objects=board.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) {result=objects.compactMap{($0 as? NSURL).map{$0 as URL}}}
  for type in ["NSFilenamesPboardType","public.file-url","text/uri-list"] {
   let type=NSPasteboard.PasteboardType(type)
   if let list=board.propertyList(forType:type) as? [String]{result+=urls(from:list)}
   if let text=board.string(forType:type){result+=urls(from:text.components(separatedBy:.newlines))}
  }
  if result.isEmpty,let text=board.string(forType:.string){let lines=text.components(separatedBy:.newlines).filter{!$0.isEmpty};let parsed=urls(from:lines);if parsed.count==lines.count && parsed.allSatisfy({FileManager.default.fileExists(atPath:$0.path)}){result=parsed}}
  return result.map{($0 as NSURL).filePathURL ?? $0}.reduce(into:[]){if !$0.contains($1){$0.append($1)}}
 }
}
