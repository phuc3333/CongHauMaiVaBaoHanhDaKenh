package haumai.core.service;

import haumai.core.repository.PortalReadRepository;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;

@Service
public class PortalQueryService {
    private final PortalReadRepository repository;

    public PortalQueryService(PortalReadRepository repository) {
        this.repository = repository;
    }

    public List<Map<String, Object>> warrantyBySerial(String serial) {
        return repository.findWarrantyBySerial(required(serial, "Serial"));
    }

    public List<Map<String, Object>> customerCase(String caseCode, String phone) {
        return repository.findCustomerCase(required(caseCode, "Mã hồ sơ"), required(phone, "Số điện thoại"));
    }

    public List<Map<String, Object>> products() {
        return repository.findProducts();
    }

    public List<Map<String, Object>> slaDashboard() {
        return repository.findSlaDashboard();
    }

    private static String required(String value, String label) {
        if (value == null || value.isBlank()) throw new IllegalArgumentException(label + " không được để trống");
        return value.trim();
    }
}
