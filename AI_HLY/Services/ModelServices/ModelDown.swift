//
//  ModelDown.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 12/2/25.
//
import Foundation
import SwiftData

func getModelDirectory() -> URL {
    let fileManager = FileManager.default
    let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let modelDir = appSupportDir.appendingPathComponent("LocalModels")

    if !fileManager.fileExists(atPath: modelDir.path) {
        try? fileManager.createDirectory(at: modelDir, withIntermediateDirectories: true)
    }
    return modelDir
}

func getLocalModelPath(for modelName: String) -> String? {
    let modelURL = getModelDirectory().appendingPathComponent("\(modelName).gguf")
    return FileManager.default.fileExists(atPath: modelURL.path) ? modelURL.path : nil
}

/// 负责模型下载的类，实现 URLSessionDownloadDelegate 以监听进度
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()  // 单例模式，避免重复创建
    private var downloadTasks: [URLSessionDownloadTask: (LocalModelInfo, URL)] = [:]
    
    /// 下载进度（按模型名称存储）
    @Published var downloadProgress: [String: Double] = [:]
    
    /// URLSession 配置，支持进度监听
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    /// 开始下载模型
    func downloadModel(_ model: LocalModelInfo, from urlString: String) {
        guard let modelURL = URL(string: urlString) else { return }

        let destinationURL = getModelDirectory().appendingPathComponent("\(model.name).gguf")

        print("开始下载: \(model.name) -> \(destinationURL.path)")

        let task = urlSession.downloadTask(with: modelURL)
        downloadTasks[task] = (model, destinationURL)
        downloadProgress[model.name] = 0.0  // 初始化进度
        task.resume()
    }
    
    /// 取消下载
    func cancelDownload(for model: LocalModelInfo) {
        for (task, (downloadingModel, _)) in downloadTasks where downloadingModel.name == model.name {
            task.cancel()  // 取消任务
            downloadTasks.removeValue(forKey: task)
            DispatchQueue.main.async {
                self.downloadProgress.removeValue(forKey: model.name)
            }
            print("取消下载: \(model.name)")
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    /// 监听下载进度
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let (model, _) = downloadTasks[downloadTask] {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100
            DispatchQueue.main.async {
                self.downloadProgress[model.name] = progress
            }
        }
    }
    
    /// 下载完成后，保存文件
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (model, destinationURL) = downloadTasks[downloadTask] else { return }
        downloadTasks.removeValue(forKey: downloadTask)
        
        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)  // 删除旧文件
            }
            try fileManager.moveItem(at: location, to: destinationURL)  // 移动新文件
            
            DispatchQueue.main.async {
                print("下载完成: \(model.name)")
                self.downloadProgress.removeValue(forKey: model.name)  // 移除进度
                NotificationCenter.default.post(name: .downloadCompleted, object: model.name)
            }
        } catch {
            print("文件保存失败: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let downloadCompleted = Notification.Name("downloadCompleted")
}
