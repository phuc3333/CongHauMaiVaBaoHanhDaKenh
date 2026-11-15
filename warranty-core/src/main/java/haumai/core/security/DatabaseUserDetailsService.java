package haumai.core.security;
import haumai.core.repository.TaiKhoanRepository;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class DatabaseUserDetailsService implements UserDetailsService {
    private final TaiKhoanRepository taiKhoanRepository;

    public DatabaseUserDetailsService(TaiKhoanRepository taiKhoanRepository) {
        this.taiKhoanRepository = taiKhoanRepository;
    }

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        TaiKhoanRepository.AccountCredentials account = taiKhoanRepository.findByUsername(username);
        if (account == null) throw new UsernameNotFoundException("Account not found");
        return User.withUsername(account.username())
            .password(account.passwordHash())
            .roles(account.role())
            .disabled(!account.active())
            .build();
    }
}
