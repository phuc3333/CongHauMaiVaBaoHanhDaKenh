(() => {
    const search = document.querySelector('#case-search');
    const caseLinks = () => [...document.querySelectorAll('.inbox-case')];
    const noResults = document.querySelector('#inbox-no-results');
    const messages = document.querySelector('#chat-messages');
    const feedback = document.querySelector('#chat-feedback');
    const inboxShell = document.querySelector('#inbox-shell');
    const chatBack = document.querySelector('#chat-back');

    if (messages && window.matchMedia('(max-width: 700px)').matches) {
        inboxShell?.classList.add('inbox-show-chat');
    }
    chatBack?.addEventListener('click', () => inboxShell?.classList.remove('inbox-show-chat'));

    search?.addEventListener('input', () => {
        const query = search.value.trim().toLocaleLowerCase('vi');
        let shown = 0;
        caseLinks().forEach((link) => {
            const match = (link.dataset.search || '').toLocaleLowerCase('vi').includes(query);
            link.hidden = !match;
            if (match) shown += 1;
        });
        if (noResults) noResults.hidden = shown > 0;
    });

    const renderMessages = (items) => {
        if (!messages) return;
        const wasNearBottom = messages.scrollHeight - messages.scrollTop - messages.clientHeight < 90;
        const fragment = document.createDocumentFragment();
        const divider = document.createElement('div');
        divider.className = 'chat-date-divider';
        const dividerText = document.createElement('span');
        dividerText.textContent = messages.dataset.conversation === 'true'
            ? 'Cuộc trò chuyện với khách'
            : 'Trao đổi về hồ sơ này';
        divider.append(dividerText);
        fragment.append(divider);

        if (!items.length) {
            const empty = document.createElement('p');
            empty.className = 'chat-empty';
            empty.textContent = 'Chưa có tin nhắn trong cuộc trò chuyện.';
            fragment.append(empty);
        }

        items.forEach((item) => {
            const article = document.createElement('article');
            article.className = `chat-message${item.direction === 'DI' ? ' chat-message--staff' : ''}`;
            const sender = document.createElement('span');
            sender.className = 'chat-sender';
            sender.textContent = item.direction === 'DI' ? 'Nhân viên' : 'Khách hàng';
            const bubble = document.createElement('p');
            bubble.className = 'chat-bubble';
            bubble.textContent = item.content || '';
            const time = document.createElement('small');
            time.className = 'chat-time';
            time.textContent = item.time || '';
            article.append(sender, bubble, time);
            if (item.direction === 'DI' && item.status) {
                const status = document.createElement('small');
                status.className = 'chat-delivery';
                status.textContent = item.status;
                article.append(status);
            }
            fragment.append(article);
        });
        messages.replaceChildren(fragment);
        if (wasNearBottom) messages.scrollTop = messages.scrollHeight;
    };

    let loading = false;
    const refreshMessages = async () => {
        if (!messages || loading) return;
        loading = true;
        try {
            const response = await fetch(messages.dataset.messagesUrl, {
                headers: { Accept: 'application/json' },
                credentials: 'same-origin',
                cache: 'no-store'
            });
            if (response.ok) renderMessages(await response.json());
        } catch (_) {
            if (feedback) feedback.textContent = 'Mất kết nối khi cập nhật hội thoại. Đang thử lại...';
        } finally {
            loading = false;
        }
    };

    if (messages) {
        messages.scrollTop = messages.scrollHeight;
        refreshMessages();
        window.setInterval(refreshMessages, 4000);
    }

    const conversationList = document.querySelector('#conversation-list');
    const conversationCount = document.querySelector('#conversation-count');
    const renderConversations = (items) => {
        if (!conversationList) return;
        const selectedId = new URLSearchParams(window.location.search).get('conversationId');
        const fragment = document.createDocumentFragment();
        items.forEach((item) => {
            const isZalo = String(item.channel || '').toUpperCase() === 'ZALO';
            const channelName = isZalo ? 'Zalo' : 'Messenger';
            const link = document.createElement('a');
            link.className = `inbox-case inbox-thread${String(item.id) === selectedId ? ' inbox-case--active' : ''}`;
            link.href = `/nhan-vien/ho-so?conversationId=${encodeURIComponent(item.id)}`;
            link.dataset.search = `${item.senderId || ''} ${channelName} ${item.preview || ''}`;

            const avatar = document.createElement('span');
            avatar.className = 'inbox-avatar';
            avatar.textContent = isZalo ? 'Z' : 'M';
            const copy = document.createElement('span');
            copy.className = 'inbox-case-copy';
            const top = document.createElement('span');
            top.className = 'inbox-case-top';
            const title = document.createElement('strong');
            title.textContent = `Khách ${channelName} ${item.id}`;
            const updated = document.createElement('small');
            updated.textContent = item.updatedAt || '';
            top.append(title, updated);
            const preview = document.createElement('span');
            preview.className = 'inbox-case-preview';
            preview.textContent = item.preview || 'Chưa có tin nhắn';
            const status = document.createElement('span');
            status.className = 'inbox-channel';
            status.textContent = `${channelName} · ${item.caseId == null ? 'Chưa có hồ sơ' : `Đã liên kết hồ sơ ${item.caseId}`}`;
            copy.append(top, preview, status);
            link.append(avatar, copy);
            fragment.append(link);
        });
        conversationList.replaceChildren(fragment);
        if (conversationCount) conversationCount.textContent = String(items.length);
        const query = search?.value.trim().toLocaleLowerCase('vi') || '';
        if (query) {
            let shown = 0;
            caseLinks().forEach((link) => {
                const match = (link.dataset.search || '').toLocaleLowerCase('vi').includes(query);
                link.hidden = !match;
                if (match) shown += 1;
            });
            if (noResults) noResults.hidden = shown > 0;
        }
    };
    const refreshConversations = async () => {
        if (!conversationList) return;
        try {
            const response = await fetch('/nhan-vien/ho-so/cuoc-tro-chuyen', {
                headers: { Accept: 'application/json' }, credentials: 'same-origin', cache: 'no-store'
            });
            if (response.ok) renderConversations(await response.json());
        } catch (_) { /* Keep the last inbox snapshot visible while offline. */ }
    };
    if (conversationList) window.setInterval(refreshConversations, 4000);

    document.querySelectorAll('[data-chat-form]').forEach((form) => {
        form.addEventListener('submit', async (event) => {
            event.preventDefault();
            const button = form.querySelector('button[type="submit"]');
            const textarea = form.querySelector('textarea[name="noiDung"]');
            if (!textarea?.value.trim()) return;
            if (button) button.disabled = true;
            if (feedback) feedback.textContent = 'Đang gửi...';
            try {
                const response = await fetch(form.action, {
                    method: 'POST',
                    body: new FormData(form),
                    headers: { 'X-Requested-With': 'XMLHttpRequest', Accept: 'application/json' },
                    credentials: 'same-origin'
                });
                const result = await response.json();
                if (!response.ok) throw new Error(result.message || result.error || 'Chưa gửi được tin nhắn.');
                textarea.value = '';
                if (feedback) feedback.textContent = result.message || 'Đã đưa tin nhắn vào hàng gửi.';
                await refreshMessages();
            } catch (error) {
                if (feedback) feedback.textContent = error.message || 'Có lỗi khi gửi tin nhắn.';
            } finally {
                if (button) button.disabled = false;
                textarea?.focus();
            }
        });
    });
})();
