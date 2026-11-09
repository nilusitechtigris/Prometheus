import Foundation

/// The only sites the harness may read. Subdomains are included, so wikipedia.org covers
/// en.wikipedia.org. Enforced in code: the model has no way around it.
struct TrustedSite: Identifiable {
    enum Purpose: String, CaseIterable, Identifiable {
        case reference = "Reference"
        case science = "Science"
        case math = "Math"
        case programming = "Programming"
        case standards = "Standards & security"
        case health = "Health"
        case government = "Government & law"
        case data = "Data & economics"
        case news = "News"
        case learning = "Learning & culture"

        var id: String { rawValue }
    }

    let domain: String
    let name: String
    let purpose: Purpose

    var id: String { domain }
}

enum TrustedSites {
    private static func sites(_ purpose: TrustedSite.Purpose, _ list: [(String, String)]) -> [TrustedSite] {
        list.map { TrustedSite(domain: $0.0, name: $0.1, purpose: purpose) }
    }

    static let all: [TrustedSite] =
        sites(.reference, [
            ("wikipedia.org", "Wikipedia"), ("wikidata.org", "Wikidata"), ("wiktionary.org", "Wiktionary"),
            ("britannica.com", "Britannica"), ("plato.stanford.edu", "Stanford Encyclopedia of Philosophy"),
            ("iep.utm.edu", "Internet Encyclopedia of Philosophy"), ("merriam-webster.com", "Merriam-Webster"),
            ("etymonline.com", "Online Etymology Dictionary"), ("worldhistory.org", "World History Encyclopedia"),
            ("si.edu", "Smithsonian Institution"),
        ])
        + sites(.science, [
            ("nature.com", "Nature"), ("science.org", "Science"), ("scientificamerican.com", "Scientific American"),
            ("nasa.gov", "NASA"), ("esa.int", "European Space Agency"), ("nist.gov", "NIST"),
            ("pubchem.ncbi.nlm.nih.gov", "PubChem"), ("rsc.org", "Royal Society of Chemistry"),
            ("usgs.gov", "US Geological Survey"), ("noaa.gov", "NOAA"), ("home.cern", "CERN"), ("aps.org", "American Physical Society"),
        ])
        + sites(.math, [
            ("arxiv.org", "arXiv"), ("mathworld.wolfram.com", "MathWorld"), ("oeis.org", "OEIS"), ("ams.org", "American Mathematical Society"),
            ("mathshistory.st-andrews.ac.uk", "MacTutor History of Mathematics"), ("ncatlab.org", "nLab"),
            ("maa.org", "Mathematical Association of America"), ("projecteuclid.org", "Project Euclid"),
        ])
        + sites(.programming, [
            ("developer.mozilla.org", "MDN Web Docs"), ("docs.python.org", "Python docs"), ("developer.apple.com", "Apple Developer"),
            ("learn.microsoft.com", "Microsoft Learn"), ("docs.oracle.com", "Oracle Docs"), ("doc.rust-lang.org", "Rust docs"),
            ("go.dev", "Go"), ("nodejs.org", "Node.js"), ("typescriptlang.org", "TypeScript"), ("docs.swift.org", "Swift docs"),
            ("cppreference.com", "cppreference"), ("postgresql.org", "PostgreSQL"), ("sqlite.org", "SQLite"), ("git-scm.com", "Git"),
            ("docs.github.com", "GitHub Docs"), ("kubernetes.io", "Kubernetes"), ("docs.docker.com", "Docker Docs"), ("stackoverflow.com", "Stack Overflow"),
        ])
        + sites(.standards, [
            ("rfc-editor.org", "RFC Editor"), ("ietf.org", "IETF"), ("w3.org", "W3C"), ("owasp.org", "OWASP"), ("cve.org", "CVE"),
            ("cisa.gov", "CISA"), ("unicode.org", "Unicode Consortium"), ("iso.org", "ISO"), ("ieee.org", "IEEE"), ("acm.org", "ACM"),
        ])
        + sites(.health, [
            ("who.int", "World Health Organization"), ("cdc.gov", "CDC"), ("nih.gov", "National Institutes of Health"),
            ("medlineplus.gov", "MedlinePlus"), ("mayoclinic.org", "Mayo Clinic"), ("nhs.uk", "NHS"), ("cochrane.org", "Cochrane"),
            ("fda.gov", "FDA"), ("ema.europa.eu", "European Medicines Agency"), ("clinicaltrials.gov", "ClinicalTrials.gov"),
        ])
        + sites(.government, [
            ("usa.gov", "USA.gov"), ("congress.gov", "US Congress"), ("loc.gov", "Library of Congress"), ("europa.eu", "European Union"),
            ("un.org", "United Nations"), ("gov.uk", "GOV.UK"), ("supremecourt.gov", "US Supreme Court"), ("law.cornell.edu", "Legal Information Institute"),
        ])
        + sites(.data, [
            ("worldbank.org", "World Bank"), ("imf.org", "IMF"), ("oecd.org", "OECD"), ("ourworldindata.org", "Our World in Data"),
            ("census.gov", "US Census Bureau"), ("bls.gov", "US Bureau of Labor Statistics"), ("stlouisfed.org", "Federal Reserve Bank of St. Louis"),
            ("ecb.europa.eu", "European Central Bank"),
        ])
        + sites(.news, [
            ("reuters.com", "Reuters"), ("apnews.com", "Associated Press"), ("bbc.com", "BBC"), ("npr.org", "NPR"),
            ("theguardian.com", "The Guardian"), ("pbs.org", "PBS"), ("dw.com", "Deutsche Welle"), ("france24.com", "France 24"),
        ])
        + sites(.learning, [
            ("khanacademy.org", "Khan Academy"), ("ocw.mit.edu", "MIT OpenCourseWare"), ("openstax.org", "OpenStax"),
            ("gutenberg.org", "Project Gutenberg"), ("openlibrary.org", "Open Library"), ("smithsonianmag.com", "Smithsonian Magazine"),
            ("metmuseum.org", "The Met"), ("nationalgeographic.com", "National Geographic"),
        ])

    static func isTrusted(host: String) -> Bool {
        let host = host.lowercased()
        return all.contains { host == $0.domain || host.hasSuffix("." + $0.domain) }
    }

    static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host else { return false }
        return isTrusted(host: host)
    }
}
