package haumai.core;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class WarrantyCoreApplication {
    public static void main(String[] args) {
        SpringApplication.run(WarrantyCoreApplication.class, args);
    }
}