package haumai.core.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import haumai.core.domain.HoSo;

import java.util.List;

public interface HoSoRepository extends JpaRepository<HoSo, Long> {
    List<HoSo> findAllByOrderByNgayTiepNhanDesc();
}