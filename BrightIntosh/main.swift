//
//  main.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 12.07.23.
//

import Cocoa

if cliBase() {
    exit(0)
}

// GUI app
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
