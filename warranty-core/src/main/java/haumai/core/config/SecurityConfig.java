package haumai.core.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
public class SecurityConfig {
    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http.authorizeHttpRequests(auth -> auth
            .requestMatchers("/actuator/health").permitAll()
            .requestMatchers("/", "/css/**", "/js/**", "/images/**", "/favicon.ico").permitAll()
            .requestMatchers(HttpMethod.GET, "/khach/tra-cuu").permitAll()
            .requestMatchers(HttpMethod.POST, "/khach/tra-cuu").permitAll()
            .requestMatchers(HttpMethod.GET, "/khach/kiem-tra-bao-hanh").permitAll()
            .requestMatchers(HttpMethod.POST, "/khach/kiem-tra-bao-hanh").permitAll()
            .requestMatchers("/nhan-vien/san-pham/**")
                .hasAnyRole("CSKH", "DIEU_PHOI_VIEN", "KY_THUAT_VIEN")
            .requestMatchers("/nhan-vien/sla", "/nhan-vien/sla/**")
                .hasRole("DIEU_PHOI_VIEN")
            .requestMatchers(HttpMethod.GET, "/nhan-vien/ho-so/*/xac-minh").hasRole("CSKH")
            .requestMatchers(HttpMethod.POST, "/nhan-vien/ho-so/*/xac-minh").hasRole("CSKH")
            .requestMatchers(HttpMethod.POST, "/nhan-vien/ho-so/*/dong").hasRole("CSKH")
            .requestMatchers(HttpMethod.POST, "/nhan-vien/ho-so/*/phan-hoi-zalo").hasRole("CSKH")
            .requestMatchers(HttpMethod.POST, "/nhan-vien/ho-so/*/phan-hoi-facebook").hasRole("CSKH")
            .requestMatchers(HttpMethod.GET, "/nhan-vien/ho-so/*/tin-nhan").hasRole("CSKH")
            .requestMatchers(HttpMethod.GET, "/nhan-vien/ho-so/cuoc-tro-chuyen").hasRole("CSKH")
            .requestMatchers(HttpMethod.GET, "/nhan-vien/ho-so/cuoc-tro-chuyen/*/tin-nhan").hasRole("CSKH")
            .requestMatchers(HttpMethod.POST, "/nhan-vien/ho-so/cuoc-tro-chuyen/*/phan-hoi").hasRole("CSKH")
            .requestMatchers(HttpMethod.POST, "/nhan-vien/ho-so/cuoc-tro-chuyen/*/tao-ho-so").hasRole("CSKH")
            .requestMatchers("/nhan-vien/ky-thuat-vien/**").hasRole("KY_THUAT_VIEN")
            .requestMatchers(HttpMethod.GET, "/nhan-vien/ho-so/*/phan-cong").hasRole("DIEU_PHOI_VIEN")
            .requestMatchers(HttpMethod.POST, "/nhan-vien/ho-so/*/phan-cong").hasRole("DIEU_PHOI_VIEN")
            .requestMatchers("/nhan-vien/ho-so", "/nhan-vien/ho-so/**")
                .hasAnyRole("CSKH", "DIEU_PHOI_VIEN")
            .anyRequest().authenticated()
        ).formLogin(form -> form
            .loginPage("/login")
            .defaultSuccessUrl("/", true)
            .permitAll()
        ).logout(logout -> logout
            .logoutSuccessUrl("/")
            .permitAll()
        );

        return http.build();
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
