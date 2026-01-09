//
//  ToastReducer.swift
//  TheQuickFox
//
//  Pure functions for Toast state transitions
//

import Foundation
import Cocoa

func toastReducer(_ state: ToastState, _ action: ToastAction) -> ToastState {
    var newState = state

    switch action {
    case .show(let reason, let appIcon, let appName, let responseText, let hudFrame):
        newState.isVisible = true
        newState.message = reason.shortMessage
        newState.errorDetail = reason.userMessage
        newState.responseText = responseText
        newState.appIcon = appIcon
        newState.appName = appName
        newState.hudFrame = hudFrame

    case .hide:
        newState.isVisible = false
        newState.message = ""
        newState.errorDetail = ""
        newState.responseText = ""
        newState.appIcon = nil
        newState.appName = ""
        newState.hudFrame = nil
    }

    return newState
}
