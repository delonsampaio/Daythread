//
//  HelpView.swift
//  Daythread
//
//  Created by Delon Sampaio on 5/27/26.
//

import SwiftUI

private struct FAQItem: Identifiable {
    let id = UUID()
    let section: String
    let question: String
    let answer: String
    var isPro: Bool = false
}

struct HelpView: View {
    @Environment(TripStore.self) private var store
    @State private var searchText = ""

    private var groupedSearchResults: [(section: String, items: [FAQItem])] {
        guard !searchText.isEmpty else { return [] }
        let matches = Self.allFAQs.filter {
            $0.question.localizedCaseInsensitiveContains(searchText) ||
            $0.answer.localizedCaseInsensitiveContains(searchText)
        }
        var groups: [(section: String, items: [FAQItem])] = []
        for item in matches {
            if let index = groups.firstIndex(where: { $0.section == item.section }) {
                groups[index].items.append(item)
            } else {
                groups.append((section: item.section, items: [item]))
            }
        }
        return groups
    }

    var body: some View {
        List {
            if searchText.isEmpty {
                gettingStartedSection
                timelineSection
                tripsSection
                vaultSection
                coEditingSection
                proFeaturesSection
            } else if groupedSearchResults.isEmpty {
                Text("No results for \"\(searchText)\"")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(groupedSearchResults, id: \.section) { group in
                    Section(group.section) {
                        ForEach(group.items) { item in
                            FAQRow(question: item.question, answer: item.answer, isPro: item.isPro, startExpanded: true)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search Help")
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: — Sections

    private var gettingStartedSection: some View {
        Section("Getting Started") {
            FAQRow(
                question: "How do I create my first trip?",
                answer: "Tap the Trips tab, then tap the + button. The wizard walks you through naming your trip, setting the destination and dates, and optionally adding a cover photo. Once saved, the app switches to your new trip in the Timeline."
            )
            FAQRow(
                question: "How do I switch between trips?",
                answer: "The horizontal strip at the top of the Timeline shows all your trips. Tap any trip to make it active, or swipe left and right to cycle through them."
            )
            FAQRow(
                question: "How do I add an event to my itinerary?",
                answer: "In the Timeline, tap the blue + button in the bottom-right corner to open the Add Event sheet. Choose a category (Flight, Hotel, Restaurant, Museum, Activity, etc.), fill in the details, and save."
            )
            FAQRow(
                question: "What categories of events can I add?",
                answer: "Daythread supports: Flight, Train, Bus, Ferry (transit), Hotel, Rental Property, Restaurant, Café, Bar, Museum, Attraction, Tour, Show, Activity, Sport, Hike, Shopping, and Other. Transit categories open an extended form for carrier, flight/train number, PNR, and seat."
            )
            FAQRow(
                question: "How do I reorder events in my day?",
                answer: "Long-press and drag any event card up or down to reorder it within the day. Time-Locked events cannot be dragged — they stay anchored in place."
            )
            FAQRow(
                question: "How do I edit or delete an event?",
                answer: "Long-press any event card to reveal the context menu. You can Lock/Unlock the event, or Delete it. To edit details, tap the card to open the edit sheet."
            )
        }
    }

    private var timelineSection: some View {
        Section("Timeline") {
            FAQRow(
                question: "What is a Time-Locked event?",
                answer: "A Time-Locked event is anchored to its time slot and cannot be dragged to a new position. Use it for flights, tour bookings, or any event with a fixed start time. Tap 'Lock Event' from the context menu to lock it — a padlock icon appears on the card."
            )
            FAQRow(
                question: "What does the lodging banner at the top show?",
                answer: "If you've added lodging that covers today's date, a banner appears just below the trip switcher strip showing your current accommodation. It updates automatically as your check-in and check-out dates change."
            )
            FAQRow(
                question: "How are transit events different from regular events?",
                answer: "Flight, Train, Bus, and Ferry events show a detailed card with carrier name, flight or train number, PNR code, terminal and gate, seat number, baggage claim, and timezone-corrected times. Fill in the transit details form after choosing one of these categories."
            )
            FAQRow(
                question: "Can I add notes to an event?",
                answer: "Yes. The Add/Edit Event sheet has a notes field where you can save anything relevant — confirmation numbers, meeting points, dress codes, etc."
            )
            FAQRow(
                question: "How do I add lodging to a trip?",
                answer: "From the Timeline, tap the + button and choose Hotel or Rental Property. Alternatively, go to Trips, tap your trip, and use the Lodging section. Enter check-in and check-out dates and a confirmation number. Lodging covers the whole trip, not a single day."
            )
        }
    }

    private var tripsSection: some View {
        Section("Trips") {
            FAQRow(
                question: "How are trips organised?",
                answer: "The Trips tab groups your trips into Current, Upcoming, Past, and Archived. A trip is 'Current' if today falls within its start and end dates, 'Upcoming' if it's in the future, and 'Past' after it ends."
            )
            FAQRow(
                question: "How do I archive a trip?",
                answer: "Swipe left on any trip in the Trips list and tap Archive. Archived trips are hidden from the active switcher strip but remain accessible in the Archived section so you can refer back to them."
            )
            FAQRow(
                question: "How do I delete a trip?",
                answer: "Swipe left on a trip in the Trips list and tap Delete. This permanently removes the trip and all its days, events, documents, and expenses."
            )
            FAQRow(
                question: "What are Pre-Trip Tasks?",
                answer: "Pre-Trip Tasks are a checklist you can attach to any trip for things to do before you leave — booking insurance, printing documents, packing specific items, etc. Tap a trip in the Trips tab and scroll to the Tasks section."
            )
            FAQRow(
                question: "Can I add a cover photo to a trip?",
                answer: "Yes. During trip creation, step 3 lets you pick a cover photo from your photo library. You can also update it later by tapping the trip card in the Trips list and editing the trip."
            )
        }
    }

    private var vaultSection: some View {
        Section("Vault (Documents & Expenses)") {
            FAQRow(
                question: "What can I store in the Vault?",
                answer: "The Vault holds two things: Documents (passports, visas, insurance cards, boarding passes, hotel confirmations — as PDFs or images) and Expenses (a running log of what you've spent per trip)."
            )
            FAQRow(
                question: "How do I add a document?",
                answer: "Go to Vault → Documents tab and tap +. You can import from your Files app (PDF or image), take a photo with your camera, or pick from your photo library. Give it a title and an optional expiry date."
            )
            FAQRow(
                question: "How many documents can I store for free?",
                answer: "Free users can store up to 5 documents per trip. Upgrade to Pro for unlimited document storage."
            )
            FAQRow(
                question: "How do I log an expense?",
                answer: "Go to Vault → Expenses tab and tap +. Enter the amount, currency, category (Food, Transport, Lodging, Activity, Shopping, or Other), date, and who paid. The Expenses tab shows a running total per currency."
            )
            FAQRow(
                question: "Can the app split expenses between group members?",
                answer: "Yes — expense debt splitting is a Pro feature. Once your trip is shared with co-editors (Pro), the Expenses tab shows a summary of who owes whom and the net amounts, minimising the number of transactions needed to settle up.",
                isPro: true
            )
        }
    }

    private var coEditingSection: some View {
        Section("Co-editing & Sync") {
            FAQRow(
                question: "How do I share a trip with travel companions?",
                answer: "In the Timeline, tap the people icon in the top-right corner to open Group Sync. Tap 'Invite People to This Trip' — this creates a shared CloudKit zone for the trip. Once the share is active, you can send the invite link via Messages or any app.",
                isPro: true
            )
            FAQRow(
                question: "Can co-editors change the itinerary?",
                answer: "Yes. Editors can add, reorder, lock, and delete events just like the trip owner. Viewer-role members see the itinerary in read-only mode.",
                isPro: true
            )
            FAQRow(
                question: "How quickly do changes appear for co-editors?",
                answer: "Updates arrive via CloudKit push and typically appear within a few seconds. This is not a live socket — think 'seconds, not instant'. The timeline refreshes automatically in the background.",
                isPro: true
            )
            FAQRow(
                question: "Does my data sync across my own devices?",
                answer: "Yes. If you're signed into the same iCloud account on multiple devices, your trips, events, documents, and expenses sync automatically. Changes propagate in the background without any manual action."
            )
            FAQRow(
                question: "What happens if two people edit at the same time?",
                answer: "CloudKit handles merge conflicts automatically. In most cases both edits are preserved. If two people change the same field simultaneously, the last write wins."
            )
            FAQRow(
                question: "How do I stop sharing a trip?",
                answer: "Open Group Sync (the people icon in the Timeline toolbar) and tap 'Stop Sharing'. This removes the shared CloudKit zone. Co-editors will no longer see updates.",
                isPro: true
            )
        }
    }

    private var proFeaturesSection: some View {
        Section("Pro Features") {
            FAQRow(
                question: "What's included in Daythread Pro?",
                answer: "Pro unlocks: Unlimited document storage · Expense splitting with debt minimisation · Trip sharing & co-editing with real-time CloudKit sync · ETA badges between events · Role-based permissions (admin / editor / viewer).",
                isPro: true
            )
            FAQRow(
                question: "How do I upgrade to Pro?",
                answer: "Go to the Profile tab and tap 'Upgrade to Pro'. The one-time $9.99 Lifetime purchase includes Family Sharing — everyone in your iCloud Family can use Pro features.",
                isPro: true
            )
            FAQRow(
                question: "How do I restore my Pro purchase on a new device?",
                answer: "Go to Profile → Settings and tap 'Restore Purchases'. As long as you're signed into the same Apple ID that made the original purchase, Pro will be restored instantly.",
                isPro: true
            )
            FAQRow(
                question: "What are ETA badges?",
                answer: "ETA badges appear between consecutive events on the same day and show the estimated travel time — for example, '12 min walk →'. They are calculated using Apple Maps and require a network connection.",
                isPro: true
            )
            FAQRow(
                question: "I'm not receiving Pro features after purchasing. What should I do?",
                answer: "Try restoring purchases from Profile → Settings → Restore Purchases. Make sure you're signed into the same Apple ID used to purchase. If the issue persists, email us at delon.sampaio+daythread@gmail.com with your order number."
            )
        }
    }

    // MARK: — Search index

    private static let allFAQs: [FAQItem] = [
        .init(section: "Getting Started", question: "How do I create my first trip?", answer: "Tap the Trips tab, then tap the + button. The wizard walks you through naming your trip, setting the destination and dates, and optionally adding a cover photo. Once saved, the app switches to your new trip in the Timeline."),
        .init(section: "Getting Started", question: "How do I switch between trips?", answer: "The horizontal strip at the top of the Timeline shows all your trips. Tap any trip to make it active, or swipe left and right to cycle through them."),
        .init(section: "Getting Started", question: "How do I add an event to my itinerary?", answer: "In the Timeline, tap the blue + button in the bottom-right corner to open the Add Event sheet. Choose a category (Flight, Hotel, Restaurant, Museum, Activity, etc.), fill in the details, and save."),
        .init(section: "Getting Started", question: "What categories of events can I add?", answer: "Daythread supports: Flight, Train, Bus, Ferry (transit), Hotel, Rental Property, Restaurant, Café, Bar, Museum, Attraction, Tour, Show, Activity, Sport, Hike, Shopping, and Other. Transit categories open an extended form for carrier, flight/train number, PNR, and seat."),
        .init(section: "Getting Started", question: "How do I reorder events in my day?", answer: "Long-press and drag any event card up or down to reorder it within the day. Time-Locked events cannot be dragged — they stay anchored in place."),
        .init(section: "Getting Started", question: "How do I edit or delete an event?", answer: "Long-press any event card to reveal the context menu. You can Lock/Unlock the event, or Delete it. To edit details, tap the card to open the edit sheet."),
        .init(section: "Timeline", question: "What is a Time-Locked event?", answer: "A Time-Locked event is anchored to its time slot and cannot be dragged to a new position. Use it for flights, tour bookings, or any event with a fixed start time. Tap 'Lock Event' from the context menu to lock it — a padlock icon appears on the card."),
        .init(section: "Timeline", question: "What does the lodging banner at the top show?", answer: "If you've added lodging that covers today's date, a banner appears just below the trip switcher strip showing your current accommodation. It updates automatically as your check-in and check-out dates change."),
        .init(section: "Timeline", question: "How are transit events different from regular events?", answer: "Flight, Train, Bus, and Ferry events show a detailed card with carrier name, flight or train number, PNR code, terminal and gate, seat number, baggage claim, and timezone-corrected times."),
        .init(section: "Timeline", question: "Can I add notes to an event?", answer: "Yes. The Add/Edit Event sheet has a notes field where you can save anything relevant — confirmation numbers, meeting points, dress codes, etc."),
        .init(section: "Timeline", question: "How do I add lodging to a trip?", answer: "From the Timeline, tap the + button and choose Hotel or Rental Property. Alternatively, go to Trips, tap your trip, and use the Lodging section. Enter check-in and check-out dates and a confirmation number."),
        .init(section: "Trips", question: "How are trips organised?", answer: "The Trips tab groups your trips into Current, Upcoming, Past, and Archived. A trip is 'Current' if today falls within its start and end dates."),
        .init(section: "Trips", question: "How do I archive a trip?", answer: "Swipe left on any trip in the Trips list and tap Archive. Archived trips are hidden from the active switcher strip but remain accessible in the Archived section."),
        .init(section: "Trips", question: "How do I delete a trip?", answer: "Swipe left on a trip in the Trips list and tap Delete. This permanently removes the trip and all its days, events, documents, and expenses."),
        .init(section: "Trips", question: "What are Pre-Trip Tasks?", answer: "Pre-Trip Tasks are a checklist you can attach to any trip for things to do before you leave — booking insurance, printing documents, packing specific items, etc."),
        .init(section: "Trips", question: "Can I add a cover photo to a trip?", answer: "Yes. During trip creation, step 3 lets you pick a cover photo from your photo library. You can also update it later by editing the trip."),
        .init(section: "Vault (Documents & Expenses)", question: "What can I store in the Vault?", answer: "The Vault holds Documents (passports, visas, insurance cards, boarding passes — as PDFs or images) and Expenses (a running log of what you've spent per trip)."),
        .init(section: "Vault (Documents & Expenses)", question: "How do I add a document?", answer: "Go to Vault → Documents tab and tap +. Import from Files, take a photo, or pick from your library. Give it a title and an optional expiry date."),
        .init(section: "Vault (Documents & Expenses)", question: "How many documents can I store for free?", answer: "Free users can store up to 5 documents per trip. Upgrade to Pro for unlimited document storage."),
        .init(section: "Vault (Documents & Expenses)", question: "How do I log an expense?", answer: "Go to Vault → Expenses tab and tap +. Enter the amount, currency, category, date, and who paid."),
        .init(section: "Vault (Documents & Expenses)", question: "Can the app split expenses between group members?", answer: "Yes — expense debt splitting is a Pro feature. The Expenses tab shows a summary of who owes whom and the net amounts.", isPro: true),
        .init(section: "Co-editing & Sync", question: "How do I share a trip with travel companions?", answer: "In the Timeline, tap the people icon in the top-right corner to open Group Sync. Tap 'Invite People to This Trip'.", isPro: true),
        .init(section: "Co-editing & Sync", question: "Can co-editors change the itinerary?", answer: "Yes. Editors can add, reorder, lock, and delete events just like the trip owner.", isPro: true),
        .init(section: "Co-editing & Sync", question: "How quickly do changes appear for co-editors?", answer: "Updates arrive via CloudKit push and typically appear within a few seconds.", isPro: true),
        .init(section: "Co-editing & Sync", question: "Does my data sync across my own devices?", answer: "Yes. If you're signed into the same iCloud account on multiple devices, your trips, events, documents, and expenses sync automatically."),
        .init(section: "Co-editing & Sync", question: "What happens if two people edit at the same time?", answer: "CloudKit handles merge conflicts automatically. In most cases both edits are preserved."),
        .init(section: "Co-editing & Sync", question: "How do I stop sharing a trip?", answer: "Open Group Sync (the people icon in the Timeline toolbar) and tap 'Stop Sharing'.", isPro: true),
        .init(section: "Pro Features", question: "What's included in Daythread Pro?", answer: "Pro unlocks: Unlimited document storage · Expense splitting · Trip sharing & co-editing · ETA badges between events · Role-based permissions.", isPro: true),
        .init(section: "Pro Features", question: "How do I upgrade to Pro?", answer: "Go to the Profile tab and tap 'Upgrade to Pro'. The one-time $9.99 Lifetime purchase includes Family Sharing.", isPro: true),
        .init(section: "Pro Features", question: "How do I restore my Pro purchase on a new device?", answer: "Go to Profile → Settings and tap 'Restore Purchases'.", isPro: true),
        .init(section: "Pro Features", question: "What are ETA badges?", answer: "ETA badges appear between consecutive events on the same day and show the estimated travel time — for example, '12 min walk →'.", isPro: true),
        .init(section: "Pro Features", question: "I'm not receiving Pro features after purchasing. What should I do?", answer: "Try restoring purchases from Profile → Settings → Restore Purchases. If the issue persists, email delon.sampaio+daythread@gmail.com with your order number."),
    ]
}

// MARK: — FAQRow

private struct FAQRow: View {
    @Environment(TripStore.self) private var store
    let question: String
    let answer: String
    var isPro: Bool = false
    var startExpanded: Bool = false
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(answer)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Text(question)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                if isPro && !store.isPro {
                    Text("PRO")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ThemeTokens.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .onAppear { if startExpanded { expanded = true } }
    }
}
