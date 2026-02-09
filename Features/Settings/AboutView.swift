//
//  AboutView.swift
//  Hoshi Reader
//
//  Copyright © 2026 Manhhao.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
    
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(version) (\(build))")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Link(destination: URL(string: "https://github.com/Manhhao/Hoshi-Reader")!) {
                    Label("GitHub", systemImage: "link")
                }
            }
            
            Section("Dependencies") {
                LicenseRow(
                    name: "AEXML",
                    license: "MIT",
                    url: "https://github.com/tadija/AEXML",
                    text: mitLicense(copyright: "Copyright (c) 2014-2024 Marko Tadić (https://markotadic.com)")
                )
                LicenseRow(
                    name: "ZipArchive",
                    license: "MIT",
                    url: "https://github.com/ZipArchive/ZipArchive",
                    text: mitLicense(copyright: "Copyright (c) 2013-2021, ZipArchive, https://github.com/ZipArchive")
                )
                LicenseRow(
                    name: "zip",
                    license: "MIT",
                    url: "https://github.com/kuba--/zip",
                    text: mitLicense(copyright: "All Rights Reserved")
                )
                LicenseRow(
                    name: "zstd",
                    license: "BSD-3",
                    url: "https://github.com/facebook/zstd",
                    text: bsdLicense
                )
                LicenseRow(
                    name: "EPUBKit",
                    license: "MIT",
                    url: "https://github.com/witekbobrowski/EPUBKit",
                    text: mitLicense(copyright: "Copyright (c) 2022 Witek Bobrowski")
                )
                LicenseRow(
                    name: "yomitandicts-cpp",
                    license: "GPLv3",
                    url: "https://github.com/Manhhao/yomitandicts-cpp",
                    text: nil
                )
            }
            
            Section("Attribution") {
                LicenseRow(
                    name: "Ankiconnect Android",
                    license: "GPLv3",
                    url: "https://github.com/KamWithK/AnkiconnectAndroid",
                    text: nil
                )
                LicenseRow(
                    name: "Yomitan",
                    license: "GPLv3",
                    url: "https://github.com/yomidevs/yomitan",
                    text: nil
                )
                LicenseRow(
                    name: "JMdict for Yomitan",
                    license: "MIT",
                    url: "https://github.com/yomidevs/jmdict-yomitan",
                    text: nil
                )
                LicenseRow(
                    name: "Jiten",
                    license: "Apache-2.0",
                    url: "https://github.com/Sirush/Jiten",
                    text: nil
                )
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var bsdLicense: String {
        """
        BSD License
        
        For Zstandard software
        
        Copyright (c) Meta Platforms, Inc. and affiliates. All rights reserved.
        
        Redistribution and use in source and binary forms, with or without modification,
        are permitted provided that the following conditions are met:
        
         * Redistributions of source code must retain the above copyright notice, this
           list of conditions and the following disclaimer.
        
         * Redistributions in binary form must reproduce the above copyright notice,
           this list of conditions and the following disclaimer in the documentation
           and/or other materials provided with the distribution.
        
         * Neither the name Facebook, nor Meta, nor the names of its contributors may
           be used to endorse or promote products derived from this software without
           specific prior written permission.
        
        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
        ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
        WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
        DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
        ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
        (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
        LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
        ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
        (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
        SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
        """
    }
    
    private func mitLicense(copyright: String) -> String {
        """
        MIT License
        
        \(copyright)
        
        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:
        
        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.
        
        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.
        """
    }
}

private struct LicenseRow: View {
    let name: String
    let license: String
    let url: String
    let text: String?
    
    var body: some View {
        if let text {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Link("GitHub", destination: URL(string: url)!)
                        .font(.caption)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } label: {
                label
            }
        } else {
            Link(destination: URL(string: url)!) {
                label
            }
        }
    }
    
    private var label: some View {
        HStack {
            Text(name)
            Spacer()
            Text(license)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
