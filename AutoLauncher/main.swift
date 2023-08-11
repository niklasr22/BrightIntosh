//
//  main.swift
//  AutoLauncher
//
//  Created by Niklas Rousset on 11.08.23.
//

import Cocoa

let application = NSApplication.shared

let delegate = LauncherAppDelegate()
application.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
