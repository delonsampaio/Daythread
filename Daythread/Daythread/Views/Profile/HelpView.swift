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
                answer: "Tap the Trips tab, then tap the + button. A single form lets you name your trip, set the destination and dates, and optionally add a cover photo. Once saved, the app switches to your new trip in the Timeline."
            )
            FAQRow(
                question: "How do I switch between trips?",
                answer: "Tap the trip name in the centre of the Timeline navigation bar — it shows a dropdown of all your active trips. The current trip's date range appears just below the name so you always know which trip you're viewing."
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
                answer: "Long-press and drag any event card to reorder it. You can also drag events between days — drop onto a different day's section and it moves there automatically. Time-Locked events cannot be dragged and will block any drop that would push them out of their time slot. If any timed events end up out of chronological order, their time label turns amber and a \"Sort by Time\" button appears in the day header — tap it to instantly restore chronological order."
            )
            FAQRow(
                question: "How do I edit or delete an event?",
                answer: "Swipe left on any event card to reveal three actions: Edit, Lock/Unlock, and Delete. Tap the action you want, or swipe right to dismiss. Time-Locked events show Unlock instead of Lock."
            )
            FAQRow(
                question: "What happens if I add an event that overlaps another?",
                answer: "When you save a timed event whose start–end window overlaps another timed event on the same day, Daythread shows an alert naming the conflicting event(s). You can tap \"Adjust Time\" to return to the form and fix the times, or \"Save Anyway\" to keep the overlap — for example, when two people are splitting up for part of the day."
            )
        }
    }

    private var timelineSection: some View {
        Section("Timeline") {
            FAQRow(
                question: "What is a Time-Locked event?",
                answer: "A Time-Locked event is anchored to its time slot. It cannot be dragged, and other events cannot be dragged past it — if you try, the card snaps back with a warning vibration. When you set a start time on a new event the lock is suggested automatically. A padlock icon (amber) appears on the card, and an amber warning badge appears if the event is currently out of order."
            )
            FAQRow(
                question: "What does the lodging banner at the top show?",
                answer: "If you've added lodging that covers today's date, a banner appears at the top of the Timeline showing your current accommodation. It updates automatically as your check-in and check-out dates change."
            )
            FAQRow(
                question: "How are transit events different from regular events?",
                answer: "Flight, Train, Bus, and Ferry events show a detailed card with carrier name, flight or train number, booking code, terminal and gate, seat number, baggage claim, and timezone-corrected times. Fill in the transit details form after choosing one of these categories."
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
                question: "How do I edit a trip?",
                answer: "Long-press any trip card in the Trips list and tap Edit. You can change the name, destination, cover photo, and dates. If you shorten the date range and any events fall outside the new dates, the app warns you with an exact count before deleting them."
            )
            FAQRow(
                question: "How do I archive a trip?",
                answer: "Long-press any trip card in the Trips list and tap Archive. Archived trips are hidden from the Timeline trip picker and the Vault, but remain accessible in the Archived section of the Trips tab so you can refer back to them."
            )
            FAQRow(
                question: "How do I delete a trip?",
                answer: "Long-press any trip card in the Trips list and tap Delete. This permanently removes the trip and all its days, events, documents, and expenses."
            )
            FAQRow(
                question: "What are Pre-Trip Tasks?",
                answer: "Pre-Trip Tasks are a checklist you can attach to any trip for things to do before you leave — booking insurance, printing documents, packing specific items, etc. Tap a trip in the Trips tab and scroll to the Tasks section."
            )
            FAQRow(
                question: "Can I add a cover photo to a trip?",
                answer: "Yes. The trip creation form has a Cover Photo section where you can pick one from your photo library. You can also change or remove it later — long-press the trip card and tap Edit, then use the Cover Photo section."
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
                question: "Can I edit a document after adding it?",
                answer: "Yes. Long-press any document tile and tap Edit Details to change the title or expiry date. The file itself cannot be replaced — delete the document and re-add it if you need to swap the file."
            )
            FAQRow(
                question: "How do I share a document?",
                answer: "Tap a document tile to open the full-screen viewer, then tap the share icon in the top-left corner to forward it via Messages, email, AirDrop, or any other app."
            )
            FAQRow(
                question: "What does the expiry badge on a document tile mean?",
                answer: "A red badge means the document is expired or expires within 30 days — renew it immediately. An amber badge means it expires within 90 days, giving you time to act before most international entry requirements (many countries require a passport valid for at least 6 months beyond your entry date)."
            )
            FAQRow(
                question: "How many documents can I store for free?",
                answer: "Free users can store up to 5 documents per trip. Upgrade to Pro for unlimited document storage."
            )
            FAQRow(
                question: "How do I log an expense?",
                answer: "Go to Vault → Expenses tab and tap +. Enter the amount, currency, category (Food, Transport, Lodging, Activity, Shopping, or Other), date, and who paid. If participants are set up for the trip, selecting a payer is required. The Expenses tab shows a running total per currency."
            )
            FAQRow(
                question: "Can I attach a receipt to an expense?",
                answer: "Yes — Pro users can attach a receipt photo to any expense. When adding or editing an expense, tap \"Attach Receipt Photo\" to take a photo with your camera or choose one from your library. A thumbnail appears on the expense row; tap it to view the full receipt.",
                isPro: true
            )
            FAQRow(
                question: "How do I split expenses with my travel group?",
                answer: "In the Vault → Expenses tab, tap the ↻ icon in the top-right toolbar (Pro). Add participant names (e.g. \"Me\", \"Alice\", \"Bob\") — no app account required. When logging expenses, choose who paid and who to split it among. The app calculates the easiest way to settle debts with the fewest transactions.\n\nIf any expenses have no payer assigned, an orange warning appears — tap it to open \"Assign Payers\" and quickly fix them. Tap Settle on any debt row to record a payment.\n\nSettlement payments appear in the expense list with a \"Settlement\" badge so you can see the full ledger history in one place.",
                isPro: true
            )
            FAQRow(
                question: "Can I settle a partial amount or overpay?",
                answer: "Yes. When you tap Settle, the amount is pre-filled with the full debt but you can edit it. Enter any amount — less for a partial payment, or more if rounding up (e.g. Venmo-style). Overpayments automatically flip the balance: if Alice over-settles by $5, the ledger shows Bob now owes Alice $5.",
                isPro: true
            )
            FAQRow(
                question: "What happens if I edit an expense after settling?",
                answer: "If you change an expense's amount, currency, payer, or split after settlements have been recorded, Daythread warns you that existing settlements may no longer be accurate. You can proceed anyway or cancel. To clean up outdated settlements, swipe to delete the relevant settlement row in the expense list and recalculate.",
                isPro: true
            )
        }
    }

    private var coEditingSection: some View {
        Section("Co-editing & Sync") {
            FAQRow(
                question: "How do I share a trip with travel companions?",
                answer: "In the Timeline, tap the people icon in the top-right corner to open Group Sync. Tap 'Invite People to This Trip' — this creates a shareable link for the trip. Once the share is active, you can send the invite link via Messages or any app.",
                isPro: true
            )
            FAQRow(
                question: "Can co-editors change the itinerary?",
                answer: "Yes. Editors can add, reorder, lock, and delete events just like the trip owner. Viewer-role members see the itinerary in read-only mode.",
                isPro: true
            )
            FAQRow(
                question: "How quickly do changes appear for co-editors?",
                answer: "Updates sync over the internet and typically appear within a few seconds. The timeline refreshes automatically in the background.",
                isPro: true
            )
            FAQRow(
                question: "Does my data sync across my own devices?",
                answer: "Yes. If you're signed into the same iCloud account on multiple devices, your trips, events, documents, and expenses sync automatically. Changes propagate in the background without any manual action."
            )
            FAQRow(
                question: "What happens if two people edit at the same time?",
                answer: "The app automatically merges changes made at the same time. If two people edit the exact same detail simultaneously, the most recent change is saved."
            )
            FAQRow(
                question: "How do I add or remove people after sharing?",
                answer: "Open Group Sync and tap 'Trip is shared — Manage people & permissions'. This opens the system sharing sheet where you can add people, change each person's permission (edit or view-only), or stop sharing — without having to stop and re-invite.",
                isPro: true
            )
            FAQRow(
                question: "Why do my co-editors show as 'Owner' instead of a name?",
                answer: "That label comes from Apple's system sharing sheet, which only shows a name when you have that person saved in Contacts under their iCloud email or phone number. Daythread also keeps its own member list in Group Sync that shows real names regardless of Contacts — set yours in Settings → Your Profile → Your name. Everyone's name appears in the Members list once each person has opened Group Sync once.",
                isPro: true
            )
            FAQRow(
                question: "What happens to co-editors when I stop sharing?",
                answer: "When you stop sharing, the trip is removed from all co-editors' devices immediately — the same way stopping a shared Apple Note works. Co-editors lose access to the trip and its events, documents, and expenses. Before stopping, let them know so they can take note of anything they need.",
                isPro: true
            )
            FAQRow(
                question: "How do I stop sharing a trip?",
                answer: "Open Group Sync, tap 'Trip is shared — Manage people & permissions', then choose 'Stop Sharing' in the system sheet. Co-editors will no longer see updates.",
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
        .init(section: "Getting Started", question: "How do I create my first trip?", answer: "Tap the Trips tab, then tap the + button. A single form lets you name your trip, set the destination and dates, and optionally add a cover photo. Once saved, the app switches to your new trip in the Timeline."),
        .init(section: "Getting Started", question: "How do I switch between trips?", answer: "Tap the trip name in the centre of the Timeline navigation bar — it shows a dropdown of all your active trips. The current trip's date range appears just below the name so you always know which trip you're viewing."),
        .init(section: "Getting Started", question: "How do I add an event to my itinerary?", answer: "In the Timeline, tap the blue + button in the bottom-right corner to open the Add Event sheet. Choose a category (Flight, Hotel, Restaurant, Museum, Activity, etc.), fill in the details, and save."),
        .init(section: "Getting Started", question: "What categories of events can I add?", answer: "Daythread supports: Flight, Train, Bus, Ferry (transit), Hotel, Rental Property, Restaurant, Café, Bar, Museum, Attraction, Tour, Show, Activity, Sport, Hike, Shopping, and Other. Transit categories open an extended form for carrier, flight/train number, booking code, and seat."),
        .init(section: "Getting Started", question: "How do I reorder events in my day?", answer: "Long-press and drag any event card to reorder it. You can also drag events between days — drop onto a different day's section and it moves there automatically. Time-Locked events cannot be dragged and will block any drop that would push them out of their time slot."),
        .init(section: "Getting Started", question: "How do I edit or delete an event?", answer: "Swipe left on any event card to reveal three actions: Edit, Lock/Unlock, and Delete. Tap the action you want, or swipe right to dismiss. Time-Locked events show Unlock instead of Lock."),
        .init(section: "Timeline", question: "What is a Time-Locked event?", answer: "A Time-Locked event is anchored to its time slot. It cannot be dragged, and other events cannot be dragged past it — if you try, the card snaps back with a warning vibration. When you set a start time on a new event the lock is suggested automatically. A padlock icon (amber) appears on the card, and an amber warning badge appears if the event is currently out of order."),
        .init(section: "Timeline", question: "What does the lodging banner at the top show?", answer: "If you've added lodging that covers today's date, a banner appears at the top of the Timeline showing your current accommodation. It updates automatically as your check-in and check-out dates change."),
        .init(section: "Timeline", question: "How are transit events different from regular events?", answer: "Flight, Train, Bus, and Ferry events show a detailed card with carrier name, flight or train number, booking code, terminal and gate, seat number, baggage claim, and timezone-corrected times."),
        .init(section: "Timeline", question: "Can I add notes to an event?", answer: "Yes. The Add/Edit Event sheet has a notes field where you can save anything relevant — confirmation numbers, meeting points, dress codes, etc."),
        .init(section: "Timeline", question: "How do I add lodging to a trip?", answer: "From the Timeline, tap the + button and choose Hotel or Rental Property. Alternatively, go to Trips, tap your trip, and use the Lodging section. Enter check-in and check-out dates and a confirmation number."),
        .init(section: "Trips", question: "How are trips organised?", answer: "The Trips tab groups your trips into Current, Upcoming, Past, and Archived. A trip is 'Current' if today falls within its start and end dates."),
        .init(section: "Trips", question: "How do I edit a trip?", answer: "Long-press any trip card in the Trips list and tap Edit. You can change the name, destination, cover photo, and dates. Shortening the date range shows a warning if events would be removed."),
        .init(section: "Trips", question: "How do I archive a trip?", answer: "Long-press any trip card in the Trips list and tap Archive. Archived trips are hidden from the Timeline trip picker and the Vault, but remain accessible in the Archived section of the Trips tab."),
        .init(section: "Trips", question: "How do I delete a trip?", answer: "Long-press any trip card in the Trips list and tap Delete. This permanently removes the trip and all its days, events, documents, and expenses."),
        .init(section: "Trips", question: "What are Pre-Trip Tasks?", answer: "Pre-Trip Tasks are a checklist you can attach to any trip for things to do before you leave — booking insurance, printing documents, packing specific items, etc."),
        .init(section: "Trips", question: "Can I add a cover photo to a trip?", answer: "Yes. The trip creation form has a Cover Photo section where you can pick one from your photo library. You can also change or remove it later via the Edit option in the trip card's long-press menu."),
        .init(section: "Vault (Documents & Expenses)", question: "What can I store in the Vault?", answer: "The Vault holds Documents (passports, visas, insurance cards, boarding passes — as PDFs or images) and Expenses (a running log of what you've spent per trip)."),
        .init(section: "Vault (Documents & Expenses)", question: "How do I add a document?", answer: "Go to Vault → Documents tab and tap +. Import from Files, take a photo, or pick from your library. Give it a title and an optional expiry date."),
        .init(section: "Vault (Documents & Expenses)", question: "Can I edit a document after adding it?", answer: "Yes. Long-press the document tile and tap Edit Details to change the title or expiry date. To replace the file, delete the document and re-add it."),
        .init(section: "Vault (Documents & Expenses)", question: "How do I share a document?", answer: "Tap the tile to open the viewer, then tap the share icon in the top-left to send via Messages, email, AirDrop, or any other app."),
        .init(section: "Vault (Documents & Expenses)", question: "What does the expiry badge on a document tile mean?", answer: "Red means expired or expiring within 30 days. Amber means expiring within 90 days — time to act before international entry requirements kick in."),
        .init(section: "Vault (Documents & Expenses)", question: "How many documents can I store for free?", answer: "Free users can store up to 5 documents per trip. Upgrade to Pro for unlimited document storage."),
        .init(section: "Vault (Documents & Expenses)", question: "How do I log an expense?", answer: "Go to Vault → Expenses tab and tap +. Enter the amount, currency, category, date, and who paid. Payer is required when participants are set up."),
        .init(section: "Vault (Documents & Expenses)", question: "Can I attach a receipt to an expense?", answer: "Yes — Pro users can attach a receipt photo to any expense. Tap 'Attach Receipt Photo' to use your camera or photo library. A thumbnail appears on the expense row; tap it to view full screen.", isPro: true),
        .init(section: "Vault (Documents & Expenses)", question: "How do I split expenses with my travel group?", answer: "In the Vault → Expenses tab, tap the ↻ icon in the top-right toolbar (Pro). Add participant names, choose who paid each expense, and the app calculates the easiest way to settle debts with the fewest transactions. An orange warning appears for expenses with no payer — tap it to assign payers. Settlement payments appear in the expense list with a Settlement badge.", isPro: true),
        .init(section: "Vault (Documents & Expenses)", question: "Can I settle a partial amount or overpay?", answer: "Yes. Tap Settle on any debt row and edit the pre-filled amount. Overpayments automatically flip the balance in the ledger.", isPro: true),
        .init(section: "Vault (Documents & Expenses)", question: "What happens if I edit an expense after settling?", answer: "Daythread warns you that existing settlements may no longer be accurate if you change the amount, currency, payer, or split after settlements exist. To clean up, swipe to delete the outdated settlement in the expense list.", isPro: true),
        .init(section: "Co-editing & Sync", question: "How do I share a trip with travel companions?", answer: "In the Timeline, tap the people icon in the top-right corner to open Group Sync. Tap 'Invite People to This Trip' to create a shareable link.", isPro: true),
        .init(section: "Co-editing & Sync", question: "Can co-editors change the itinerary?", answer: "Yes. Editors can add, reorder, lock, and delete events just like the trip owner.", isPro: true),
        .init(section: "Co-editing & Sync", question: "How quickly do changes appear for co-editors?", answer: "Updates sync over the internet and typically appear within a few seconds.", isPro: true),
        .init(section: "Co-editing & Sync", question: "Does my data sync across my own devices?", answer: "Yes. If you're signed into the same iCloud account on multiple devices, your trips, events, documents, and expenses sync automatically."),
        .init(section: "Co-editing & Sync", question: "What happens if two people edit at the same time?", answer: "The app automatically merges changes made at the same time. If two people edit the exact same detail simultaneously, the most recent change is saved."),
        .init(section: "Co-editing & Sync", question: "How do I add or remove people after sharing?", answer: "Open Group Sync and tap 'Trip is shared — Manage people & permissions' to add people, change permissions, or stop sharing — no need to stop and re-invite.", isPro: true),
        .init(section: "Co-editing & Sync", question: "Why do my co-editors show as 'Owner' instead of a name?", answer: "Apple's system sharing sheet only shows names for people in your Contacts. Set your name in Settings → Your Profile so co-editors see it in Daythread's own Members list, regardless of Contacts.", isPro: true),
        .init(section: "Co-editing & Sync", question: "How do I stop sharing a trip?", answer: "Open Group Sync, tap 'Trip is shared — Manage people & permissions', then choose 'Stop Sharing' in the system sheet.", isPro: true),
        .init(section: "Pro Features", question: "What's included in Daythread Pro?", answer: "Pro unlocks: Unlimited document storage · Receipt photo attachments on expenses · Expense splitting with debt minimisation · Trip sharing & co-editing · ETA badges between events · Role-based permissions.", isPro: true),
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
