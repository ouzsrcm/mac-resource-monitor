/// Sabit kapasiteli halka tampon. Kapasite dolduğunda en eski eleman
/// üzerine yazılır; böylece bellek kullanımı sabit kalır.
struct RingBuffer<Element> {
    let capacity: Int
    private var storage: [Element] = []
    /// Tampon dolduktan sonra bir sonraki yazmanın yapılacağı (yani en eski
    /// elemanın bulunduğu) indeks.
    private var head = 0

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer kapasitesi pozitif olmalı")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Elemanlar en eskiden en yeniye sıralı.
    var elements: [Element] {
        Array(storage[head...] + storage[..<head])
    }

    var last: Element? {
        guard !storage.isEmpty else { return nil }
        return storage[(head + storage.count - 1) % storage.count]
    }
}

extension RingBuffer: Sendable where Element: Sendable {}
