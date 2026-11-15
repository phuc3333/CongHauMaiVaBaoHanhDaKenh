package haumai.core.service;

import haumai.core.repository.HoSoReadRepository;
import org.springframework.stereotype.Service;
import java.util.List;
import java.util.Map;

@Service
public class HoSoQueryService {
    private final HoSoReadRepository repository;
    public HoSoQueryService(HoSoReadRepository repository) { this.repository = repository; }
    public List<Map<String, Object>> slas() { return repository.slas(); }
    public List<Map<String, Object>> techniciansByCase() { return repository.techniciansByCase(); }
    public List<Map<String, Object>> customerByCase() { return repository.customerByCase(); }
    public List<Map<String, Object>> openConversations() { return repository.openConversations(); }
    public List<Long> zaloCaseIds() { return repository.caseIdsForChannel("public.v_ho_so_zalo"); }
    public List<Long> facebookCaseIds() { return repository.caseIdsForChannel("public.v_ho_so_facebook"); }
    public List<Map<String, Object>> conversation(Long id) { return repository.conversation(id); }
    public Map<String, Object> editForm(Long id) { return repository.editForm(id); }
    public Map<String, Object> assignmentForm(Long id) { return repository.assignmentForm(id); }
    public List<Map<String, Object>> technicians() { return repository.technicians(); }
    public Map<String, Object> verificationForm(Long id) { return repository.verificationForm(id); }
}
