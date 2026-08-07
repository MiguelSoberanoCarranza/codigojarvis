import Foundation
import CoreLocation

struct IPLocation: Codable {
    let latitude: Double
    let longitude: Double
    let city: String
    
    static var `default`: IPLocation {
        return IPLocation(latitude: 17.9862, longitude: -92.9393, city: "Villahermosa")
    }
}

struct OpenMeteoResponse: Codable {
    struct CurrentWeather: Codable {
        let temperature_2m: Double
        let weather_code: Int
    }
    let current: CurrentWeather
}

class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var temperature: String = "--°C"
    @Published var city: String = "Detectando..."
    @Published var conditionEmoji: String = "🌡️"
    @Published var conditionText: String = "Desconocido"
    
    private var timer: Timer?
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        
        refreshWeather()
        
        // Refresh weather every 15 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            self?.refreshWeather()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func refreshWeather() {
        if CLLocationManager.locationServicesEnabled() {
            let status = locationManager.authorizationStatus
            if status == .authorizedAlways || status == .authorized {
                locationManager.requestLocation()
            } else if status == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            } else {
                fetchNetworkLocation()
            }
        } else {
            fetchNetworkLocation()
        }
    }
    
    // MARK: - CoreLocation Delegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            let cityName = placemarks?.first?.locality ?? placemarks?.first?.name ?? "Mi Ubicación"
            let ipLoc = IPLocation(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, city: cityName)
            self?.fetchWeather(for: ipLoc)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fetchNetworkLocation()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorized {
            manager.requestLocation()
        } else {
            fetchNetworkLocation()
        }
    }
    
    // MARK: - Secure HTTPS Network Location Fallback
    private func fetchNetworkLocation() {
        guard let url = URL(string: "https://ipinfo.io/json") else {
            self.fetchWeather(for: IPLocation.default)
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                self?.fetchWeather(for: IPLocation.default)
                return
            }
            
            struct IPInfoResponse: Codable {
                let city: String?
                let loc: String?
            }
            
            do {
                let res = try JSONDecoder().decode(IPInfoResponse.self, from: data)
                let cityName = res.city ?? "Villahermosa"
                var lat = 17.9862
                var lon = -92.9393
                
                if let locString = res.loc {
                    let parts = locString.components(separatedBy: ",")
                    if parts.count == 2, let l1 = Double(parts[0]), let l2 = Double(parts[1]) {
                        lat = l1
                        lon = l2
                    }
                }
                
                let ipLoc = IPLocation(latitude: lat, longitude: lon, city: cityName)
                self?.fetchWeather(for: ipLoc)
            } catch {
                self?.fetchWeather(for: IPLocation.default)
            }
        }.resume()
    }
    
    private func fetchWeather(for location: IPLocation) {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(location.latitude)&longitude=\(location.longitude)&current=temperature_2m,weather_code"
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else { return }
            
            do {
                let res = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                let temp = Int(res.current.temperature_2m.rounded())
                let code = res.current.weather_code
                
                let (emoji, description) = self?.parseWeatherCode(code) ?? ("🌡️", "Desconocido")
                
                DispatchQueue.main.async {
                    self?.temperature = "\(temp)°C"
                    self?.city = location.city
                    self?.conditionEmoji = emoji
                    self?.conditionText = description
                }
            } catch {
                print("Failed to decode weather: \(error)")
            }
        }.resume()
    }
    
    private func parseWeatherCode(_ code: Int) -> (String, String) {
        switch code {
        case 0:
            return ("☀️", "Despejado")
        case 1, 2, 3:
            return ("⛅", "Parcialmente Nublado")
        case 45, 48:
            return ("🌫️", "Niebla")
        case 51, 53, 55:
            return ("🌧️", "Llovizna")
        case 56, 57:
            return ("❄️🌧️", "Llovizna Helada")
        case 61, 63, 65:
            return ("🌧️", "Lluvia")
        case 66, 67:
            return ("❄️🌧️", "Lluvia Helada")
        case 71, 73, 75:
            return ("❄️", "Nieve")
        case 77:
            return ("❄️", "Granizo Fino")
        case 80, 81, 82:
            return ("🌦️", "Chubascos de Lluvia")
        case 85, 86:
            return ("❄️🌦️", "Chubascos de Nieve")
        case 95:
            return ("⛈️", "Tormenta Eléctrica")
        case 96, 99:
            return ("⛈️", "Tormenta con Granizo")
        default:
            return ("🌡️", "Desconocido")
        }
    }
}
