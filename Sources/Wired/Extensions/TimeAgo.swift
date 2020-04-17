
import Foundation



public func timeAgoSince(_ date: Date) -> String {
    
    let calendar = Calendar.current
    let now = Date()
    let unitFlags: NSCalendar.Unit = [.second, .minute, .hour, .day, .weekOfYear, .month, .year]
    let components = (calendar as NSCalendar).components(unitFlags, from: date, to: now, options: [])
    
    if let year = components.year, year >= 2 {
        let localstring = NSLocalizedString("years ago", comment: "")
        return "\(year)" + " " + localstring
    }
    
    if let year = components.year, year >= 1 {
        let localstring = NSLocalizedString("Last year", comment: "")
        return localstring
    }
    
    if let month = components.month, month >= 2 {
        let localstring = NSLocalizedString("months ago", comment: "")
        return "\(month)" + " " + localstring
    }
    
    if let month = components.month, month >= 1 {
        let localstring = NSLocalizedString("Last month", comment: "")
        return localstring
    }
    
    if let week = components.weekOfYear, week >= 2 {
        let localstring = NSLocalizedString("weeks ago", comment: "")
        return "\(week)" + " " + localstring
    }
    
    if let week = components.weekOfYear, week >= 1 {
        let localstring = NSLocalizedString("Last week", comment: "")
        return localstring
    }
    
    if let day = components.day, day >= 2 {
        let localstring = NSLocalizedString("days ago", comment: "")
        return "\(day)" + " " + localstring
    }
    
    if let day = components.day, day >= 1 {
        let localstring = NSLocalizedString("Yesterday", comment: "")
        return localstring
    }
    
    if let hour = components.hour, hour >= 2 {
        let localstring = NSLocalizedString("hours ago", comment: "")
        return "\(hour)" + " " + localstring
    }
    
    if let hour = components.hour, hour >= 1 {
        let localstring = NSLocalizedString("An hour ago", comment: "")
        return localstring
    }
    
    if let minute = components.minute, minute >= 2 {
        let localstring = NSLocalizedString("minutes ago", comment: "")
        return "\(minute)" + " " + localstring
    }
    
    if let minute = components.minute, minute >= 1 {
        let localstring = NSLocalizedString("A minute ago", comment: "")
        return localstring
    }
    
    if let second = components.second, second >= 3 {
        let localstring = NSLocalizedString("seconds ago", comment: "")
        return "\(second)" + " " + localstring
    }
    let localstring = NSLocalizedString("Just now", comment: "")
    return localstring
    
}
