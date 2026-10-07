//
//  VoiceControlSettingsView.swift
//  Nuage
//

import SwiftUI

struct VoiceControlSettingsView: View {

    @ObservedObject private var voiceService = VoiceControlService.shared
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.accentColor)

                    Text(LocalizedStringKey("voice.title"))
                        .font(.system(size: 15, weight: .bold))
                }

                Spacer()

                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Main Toggle Card
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(LocalizedStringKey("voice.manage"))
                                .font(.system(size: 13, weight: .semibold))

                            Text(LocalizedStringKey("voice.realtimeNotice"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $voiceService.isEnabled)
                            .toggleStyle(.switch)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Wake Word (Обращение)
                    if voiceService.isEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(LocalizedStringKey("voice.assistantName"))
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(String(format: NSLocalizedString("voice.nameHint", comment: ""), voiceService.wakeWord))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 8) {
                                    TextField("Sound", text: $voiceService.wakeWord)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .frame(width: 100)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                        )

                                    if voiceService.wakeWord != "Sound" {
                                        Button {
                                            voiceService.wakeWord = "Sound"
                                        } label: {
                                            Image(systemName: "arrow.counterclockwise")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help(NSLocalizedString("voice.resetNameHelp", comment: ""))
                                    }
                                }
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey("voice.requireWakeWord"))
                                        .font(.system(size: 12, weight: .medium))
                                    Text(String(format: NSLocalizedString("voice.requireWakeWordHint", comment: ""), voiceService.wakeWord))
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: $voiceService.requireWakeWord)
                                    .toggleStyle(.switch)
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // Status & Language row
                    if voiceService.isEnabled {
                        VStack(spacing: 12) {
                            // Microphone Device picker
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(LocalizedStringKey("voice.inputDevice"))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Picker("", selection: $voiceService.selectedDeviceID) {
                                        Text(LocalizedStringKey("voice.defaultSystem")).tag("default")
                                        ForEach(voiceService.availableDevices) { dev in
                                            Text(dev.name + (dev.isBuiltIn ? " (\(NSLocalizedString("voice.defaultSystem", comment: "")))" : "")).tag(dev.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: 220)
                                }

                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)

                                    Text(LocalizedStringKey("voice.airPodsNotice"))
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 2)
                            }

                            Divider()

                            // Language picker
                            HStack {
                                Text(LocalizedStringKey("voice.language"))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)

                                Spacer()

                                Picker("", selection: $voiceService.language) {
                                    ForEach(VoiceLanguage.allCases) { lang in
                                        Text(lang.title).tag(lang)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 170)
                            }

                            Divider()

                            // Visual feedback toggle
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey("voice.hudHint"))
                                        .font(.system(size: 12, weight: .medium))
                                    Text(LocalizedStringKey("voice.hudDescription"))
                                        .font(.system(size: 10.5))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Toggle("", isOn: $voiceService.showVoiceHUD)
                                    .toggleStyle(.switch)
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // Commands Cheat Sheet
                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey("voice.availableCommands"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.leading, 2)

                        let prefix = voiceService.requireWakeWord ? "\(voiceService.wakeWord) " : ""
                        VStack(spacing: 6) {
                            commandRow(icon: "forward.fill", title: NSLocalizedString("voice.cmd.next", comment: ""), phrases: formattedPhrases(for: "voice.cmd.next.phrases", prefix: prefix))
                            commandRow(icon: "backward.fill", title: NSLocalizedString("voice.cmd.prev", comment: ""), phrases: formattedPhrases(for: "voice.cmd.prev.phrases", prefix: prefix))
                            commandRow(icon: "pause.fill", title: NSLocalizedString("voice.cmd.pause", comment: ""), phrases: formattedPhrases(for: "voice.cmd.pause.phrases", prefix: prefix))
                            commandRow(icon: "play.fill", title: NSLocalizedString("voice.cmd.play", comment: ""), phrases: formattedPhrases(for: "voice.cmd.play.phrases", prefix: prefix))
                            commandRow(icon: "dot.radiowaves.left.and.right", title: NSLocalizedString("voice.cmd.wave", comment: ""), phrases: formattedPhrases(for: "voice.cmd.wave.phrases", prefix: prefix))
                            commandRow(icon: "arrow.clockwise", title: NSLocalizedString("voice.cmd.refreshWave", comment: ""), phrases: formattedPhrases(for: "voice.cmd.refreshWave.phrases", prefix: prefix))
                            commandRow(icon: "magnifyingglass", title: NSLocalizedString("voice.cmd.findTrack", comment: ""), phrases: formattedPhrases(for: "voice.cmd.findTrack.phrases", prefix: prefix))
                            commandRow(icon: "bubble.left.fill", title: NSLocalizedString("voice.cmd.comment", comment: ""), phrases: formattedPhrases(for: "voice.cmd.comment.phrases", prefix: prefix))
                            commandRow(icon: "paperplane.fill", title: NSLocalizedString("voice.cmd.sendFriend", comment: ""), phrases: formattedPhrases(for: "voice.cmd.sendFriend.phrases", prefix: prefix))
                            commandRow(icon: "heart.circle.fill", title: NSLocalizedString("voice.cmd.playLikes", comment: ""), phrases: formattedPhrases(for: "voice.cmd.playLikes.phrases", prefix: prefix))
                            commandRow(icon: "repeat.circle.fill", title: NSLocalizedString("voice.cmd.playReposts", comment: ""), phrases: formattedPhrases(for: "voice.cmd.playReposts.phrases", prefix: prefix))
                            commandRow(icon: "repeat", title: NSLocalizedString("voice.cmd.repost", comment: ""), phrases: formattedPhrases(for: "voice.cmd.repost.phrases", prefix: prefix))
                            commandRow(icon: "arrow.triangle.2.circlepath", title: NSLocalizedString("voice.cmd.unrepost", comment: ""), phrases: formattedPhrases(for: "voice.cmd.unrepost.phrases", prefix: prefix))
                            commandRow(icon: "heart.fill", title: NSLocalizedString("voice.cmd.like", comment: ""), phrases: formattedPhrases(for: "voice.cmd.like.phrases", prefix: prefix))
                            commandRow(icon: "heart.slash", title: NSLocalizedString("voice.cmd.unlike", comment: ""), phrases: formattedPhrases(for: "voice.cmd.unlike.phrases", prefix: prefix))
                            commandRow(icon: "speaker.wave.3.fill", title: NSLocalizedString("voice.cmd.volumeUp", comment: ""), phrases: formattedPhrases(for: "voice.cmd.volumeUp.phrases", prefix: prefix))
                            commandRow(icon: "speaker.wave.1.fill", title: NSLocalizedString("voice.cmd.volumeDown", comment: ""), phrases: formattedPhrases(for: "voice.cmd.volumeDown.phrases", prefix: prefix))
                            commandRow(icon: "speaker.slash.fill", title: NSLocalizedString("voice.cmd.mute", comment: ""), phrases: formattedPhrases(for: "voice.cmd.mute.phrases", prefix: prefix))
                            commandRow(icon: "shuffle", title: NSLocalizedString("voice.cmd.shuffle", comment: ""), phrases: formattedPhrases(for: "voice.cmd.shuffle.phrases", prefix: prefix))
                            commandRow(icon: "repeat", title: NSLocalizedString("voice.cmd.repeat", comment: ""), phrases: formattedPhrases(for: "voice.cmd.repeat.phrases", prefix: prefix))
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 450, height: 600)
    }

    private func formattedPhrases(for key: String, prefix: String) -> String {
        let raw = NSLocalizedString(key, comment: "")
        guard !prefix.isEmpty else { return raw }
        return raw.components(separatedBy: ", ")
            .map { "\(prefix)\($0)" }
            .joined(separator: ", ")
    }

    private func commandRow(icon: String, title: String, phrases: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 135, alignment: .leading)

            Text(phrases)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
    }
}
